/**
 * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
 *
 * v3.1.0
 *
 * PMD False Positives:
 * - CognitiveComplexity / CyclomaticComplexity / StdCyclomaticComplexity / NcssTypeCount /
 *   TooManyFields: every ordering rule of a chain lives here on purpose; result rows are
 *   written by AsyncResultWriter and settings read by QueueableJobSettings
 **/
@SuppressWarnings(
    'PMD.CognitiveComplexity,PMD.CyclomaticComplexity,PMD.StdCyclomaticComplexity,PMD.NcssTypeCount,PMD.TooManyFields'
)
public inherited sharing class QueueableChain {
    @TestVisible
    private List<QueueableJob> jobs = new List<QueueableJob>();
    @TestVisible
    private Id initialQueuableChainSchedulableId;
    private Boolean isChainedContext = false;
    private Boolean isStopped = false;
    private Integer chainCounter = 0;
    private Integer jobSequence = 0;
    private Set<String> customJobIdsBeforeAttempt;
    private Set<String> skippedCustomJobIdsBeforeAttempt;
    private Boolean wasStoppedBeforeAttempt;
    private QueueableJob currentJob;
    private Map<String, Async.Outcome> outcomeByCustomJobId = new Map<String, Async.Outcome>();
    private AsyncResultWriter resultWriter = new AsyncResultWriter();
    private String chainId;
    private String chainName;
    private Integer nextInChainSlot;

    public void execute(QueueableContext ctx) {
        QueueableManager.get().setChain(this);
        attachQueueableChainFinalizer();
        executeCurrentJob(ctx);
    }

    public void attachQueueableChainFinalizer() {
        System.attachFinalizer(new QueueableChainFinalizer(this));
    }

    // The debug output is a feature: it correlates a running job with its AsyncResult__c row.
    @SuppressWarnings('PMD.AvoidDebugStatements,PMD.DebugsShouldUseLoggingLevel')
    public void executeCurrentJob(QueueableContext ctx) {
        if (!hasNextJob()) {
            return;
        }

        currentJob = getNextJobToProcess();
        currentJob.queueableCtx = ctx;
        currentJob.salesforceJobId = ctx.getJobId();
        currentJob.setChainCounterToName(++chainCounter);
        currentJob.startedAt = System.now();
        nextInChainSlot = currentJob.chainSequence;
        customJobIdsBeforeAttempt = currentCustomJobIds();
        skippedCustomJobIdsBeforeAttempt = currentSkippedCustomJobIds();
        wasStoppedBeforeAttempt = isStopped;

        Savepoint sp = currentJob.rollbackOnJobExecuteFail ? Database.setSavepoint() : null;
        try {
            System.debug(currentJob.customJobId);
            System.debug(currentJob.uniqueName);
            // A mocked failure has to be raised in here, so it settles through the same path a
            // real one does: rollback, retry classification and result recording.
            injectQueueableMockIfNeeded(currentJob);
            currentJob.work();
        } catch (Exception ex) {
            // The live exception only exists here; classify now and capture metadata as a
            // FailureInfo so the decision + audit fields survive serialization into the finalizer.
            currentJob.recordFailure(ex);
            if (currentJob.rollbackOnJobExecuteFail) {
                Database.rollback(sp);
                Database.releaseSavepoint(sp);
            } else if (!currentJob.continueOnJobExecuteFail) {
                throw ex;
            }
        }
    }

    public void enqueueNextJobIfAnyFromFinalizer(FinalizerContext ctx) {
        QueueableJob previousJob = currentJob;
        reconcileOutcomeFromFinalizer(previousJob, ctx);

        if (previousJob.canRetry() && enqueuedRetry(previousJob)) {
            return;
        }

        // The chain rides the finalizer's serialized state, not the database, so a rolled back
        // transaction leaves it intact. Salesforce would have undone a real System.enqueueJob.
        if (attemptWasRolledBack(previousJob, ctx)) {
            revertChainChangesFromRolledBackAttempt();
        }

        if (previousJob.hasFailed && previousJob.maxRetries > 0) {
            previousJob.recordRetryHistory(previousJob.retryAttempt + 1, null);
        }

        previousJob.isProcessed = true;
        previousJob.finalizerCtx = ctx;
        recordOutcome(previousJob);
        notifyFinalFailure(previousJob);

        setFinalizerContextToAllFinalizersForPreviousJob(previousJob, ctx);
        maybeAdvanceChunkRun(previousJob);
        enqueueNextJobIfAny();
    }

    public void recordFrameworkFailure(Exception frameworkFailure) {
        resultWriter.recordFrameworkFailure(chainId, currentJob, frameworkFailure);
    }

    private void maybeAdvanceChunkRun(QueueableJob previousJob) {
        if (!(previousJob instanceof ChunkJob)) {
            return;
        }
        ChunkJob settledPage = (ChunkJob) previousJob;
        ChunkJob nextPage = settledPage.nextPageOrNull();
        if (nextPage != null) {
            addJob(nextPage);
            skipNextPageIfRunEnded(settledPage, nextPage);
        }
        if (!settledPage.getRun().keepPages) {
            removeRecordedChunkPages();
        }
    }

    private void skipNextPageIfRunEnded(ChunkJob settledPage, ChunkJob nextPage) {
        if (isStopped) {
            markSkipped(
                nextPage,
                QueueableManager.STATUS_SKIPPED_CHAIN_STOPPED,
                chainStopReason(nextPage)
            );
            return;
        }
        if (settledPage.getRun().isHaltedBy(settledPage.hasFailed)) {
            markSkipped(
                nextPage,
                QueueableManager.STATUS_SKIPPED_CHUNK_STOPPED,
                nextPage.getRun().remainingWorkSummary()
            );
        }
    }

    // A chunk run appends pages one at a time; dropping recorded pages keeps the serialized
    // chain state flat instead of piling up every page of the run.
    private void removeRecordedChunkPages() {
        for (Integer i = jobs.size() - 1; i >= 0; i--) {
            QueueableJob job = jobs[i];
            if (!(job instanceof ChunkJob) || !job.isProcessed || !job.resultCreated) {
                continue;
            }
            if (!ownsRunLevelOutcome((ChunkJob) job)) {
                outcomeByCustomJobId.remove(job.customJobId);
                resultWriter.forget(job.customJobId);
            }
            jobs.remove(i);
        }
    }

    private Boolean ownsRunLevelOutcome(ChunkJob page) {
        return page.customJobId == page.getRun().runId;
    }

    private void reconcileOutcomeFromFinalizer(QueueableJob job, FinalizerContext ctx) {
        if (ctx?.getResult() != ParentJobResult.UNHANDLED_EXCEPTION || job.hasFailed) {
            return;
        }
        // Uncatchable failures (e.g. LimitException) never hit the catch in executeCurrentJob;
        // the finalizer is the only place their exception is reachable.
        Exception ex = ctx.getException();
        if (ex != null) {
            job.recordFailure(ex);
        } else {
            job.recordUnknownFailure();
        }
    }

    private void recordOutcome(QueueableJob job) {
        outcomeByCustomJobId.put(
            job.customJobId,
            job.hasFailed ? Async.Outcome.FAILURE : Async.Outcome.SUCCESS
        );
        if (job instanceof ChunkJob) {
            recordChunkRunOutcome((ChunkJob) job);
        }
    }

    private void notifyFinalFailure(QueueableJob job) {
        if (job.skipStatus != null) {
            return;
        }
        if (!job.hasFailed) {
            AsyncEventDispatcher.jobSucceeded(job, QueueableManager.loggerClassFor(job));
            return;
        }
        job.safeOnFinalFailure(new Async.FailureContext(job));
        AsyncEventDispatcher.jobFailed(job, QueueableManager.loggerClassFor(job));
    }

    private void recordChunkRunOutcome(ChunkJob settledPage) {
        ChunkRun run = settledPage.getRun();
        Boolean anyPageFailed = run.hasFailedPage || settledPage.hasFailed;
        outcomeByCustomJobId.put(
            run.runId,
            anyPageFailed ? Async.Outcome.FAILURE : Async.Outcome.SUCCESS
        );
    }

    // A retry that cannot be prepared must not kill the finalizer, which would stop the chain
    // with no trace. Returning false lets the caller settle the job as a terminal failure.
    private Boolean enqueuedRetry(QueueableJob previousJob) {
        try {
            enqueueRetry(previousJob);
            return true;
        } catch (Exception retryFailure) {
            previousJob.recordRetryNotEnqueued(previousJob.retryAttempt + 1, retryFailure);
            return false;
        }
    }

    private void enqueueRetry(QueueableJob previousJob) {
        Integer nextAttempt = previousJob.retryAttempt + 1;
        Integer delayMinutes = previousJob.backoff?.delayMinutes(nextAttempt);

        // Clone before mutating previousJob: a clone that throws must leave it settleable. Safe
        // to move because every field the mutations touch is overwritten on the clone below.
        QueueableJob retryJob = QueueableManager.retryJobFrom(previousJob);

        previousJob.recordRetryHistory(nextAttempt, delayMinutes);
        resultWriter.updatePlaceholderForRetry(previousJob, nextAttempt, delayMinutes);
        previousJob.isProcessed = true;
        // Only the final attempt produces a result row; suppress this superseded one.
        previousJob.resultCreated = true;

        retryJob.retryAttempt = nextAttempt;
        retryJob.delay = delayMinutes;
        retryJob.asyncOptions = delayMinutes != null ? null : retryJob.asyncOptions;
        retryJob.isProcessed = false;
        retryJob.resultCreated = false;
        retryJob.hasFailed = false;
        retryJob.failure = null;
        retryJob.retryDecision = false;
        retryJob.finalizerCtx = null;
        retryJob.retryHistory = previousJob.retryHistory;
        retryJob.requeuePayload = previousJob.requeuePayload;
        retryJob.requeueStatus = previousJob.requeueStatus;
        retryJob.requeuePayloadSize = previousJob.requeuePayloadSize;
        retryJob.requeuedFromResultId = previousJob.requeuedFromResultId;
        AsyncRequeue.releasePayload(previousJob);
        QueueableManager.runRetryReset(retryJob, nextAttempt);

        revertChainChangesBeforeRetry();
        jobs.add(0, retryJob);
        AsyncEventDispatcher.retryEnqueued(
            previousJob,
            delayMinutes,
            QueueableManager.loggerClassFor(previousJob)
        );
        enqueueNextJobIfAny();
    }

    private Boolean attemptWasRolledBack(QueueableJob job, FinalizerContext ctx) {
        return ctx?.getResult() == ParentJobResult.UNHANDLED_EXCEPTION ||
            (job.hasFailed && job.rollbackOnJobExecuteFail);
    }

    private void revertChainChangesFromRolledBackAttempt() {
        restoreSkipsFromBeforeAttempt();
        discardJobsChainedByAttempt();
    }

    private void revertChainChangesBeforeRetry() {
        restoreSkipsFromBeforeAttempt();
        discardJobsChainedByAttempt();
        discardFinalizersAttachedByAttempt();
    }

    private void restoreSkipsFromBeforeAttempt() {
        if (skippedCustomJobIdsBeforeAttempt == null) {
            return;
        }
        isStopped = wasStoppedBeforeAttempt;
        for (QueueableJob job : jobs) {
            if (
                job.skipStatus == null || skippedCustomJobIdsBeforeAttempt.contains(job.customJobId)
            ) {
                continue;
            }
            job.skipStatus = null;
            job.skipReason = null;
            job.isProcessed = false;
        }
    }

    private void discardJobsChainedByAttempt() {
        for (Integer i = jobs.size() - 1; i >= 0; i--) {
            if (addedByAttempt(jobs[i]) && !jobs[i].isFinalizer) {
                discardJobAt(i);
            }
        }
    }

    private void discardFinalizersAttachedByAttempt() {
        for (Integer i = jobs.size() - 1; i >= 0; i--) {
            if (addedByAttempt(jobs[i]) && jobs[i].isFinalizer) {
                discardJobAt(i);
            }
        }
    }

    private Boolean addedByAttempt(QueueableJob job) {
        return customJobIdsBeforeAttempt != null &&
            !customJobIdsBeforeAttempt.contains(job.customJobId);
    }

    private void discardJobAt(Integer index) {
        QueueableJob job = jobs[index];
        outcomeByCustomJobId.remove(job.customJobId);
        resultWriter.forget(job.customJobId);
        jobs.remove(index);
    }

    private Set<String> currentCustomJobIds() {
        Set<String> customJobIds = new Set<String>();
        for (QueueableJob job : jobs) {
            customJobIds.add(job.customJobId);
        }
        return customJobIds;
    }

    private Set<String> currentSkippedCustomJobIds() {
        Set<String> customJobIds = new Set<String>();
        for (QueueableJob job : jobs) {
            if (job.skipStatus != null) {
                customJobIds.add(job.customJobId);
            }
        }
        return customJobIds;
    }

    private void createPendingResults() {
        List<QueueableJob> candidates = new List<QueueableJob>();
        for (QueueableJob job : jobs) {
            if (job.isProcessed && !job.resultCreated) {
                candidates.add(job);
            }
        }
        resultWriter.recordResults(candidates, outcomeByCustomJobId);
    }

    public void enqueueNextJobIfAny() {
        removeJobsThatAreDisabledAndDependentFinalizers();
        skipJobsWithUnsatisfiedDependencies();
        createPendingResults();
        if (!hasNextJob() || (Test.isRunningTest() && System.isQueueable())) {
            return;
        }

        QueueableJob nextJob = getNextJobToProcess();
        resultWriter.createEnqueuedPlaceholders(jobs, currentJob);
        try {
            isChainedContext = true;
            nextJob.enqueue(this);
        } catch (Exception ex) {
            if (!nextJob.continueOnJobEnqueueFail) {
                resultWriter.deletePlaceholdersOfUnprocessedJobs(jobs, nextJob);
                throw ex;
            }
            isChainedContext = false;
            nextJob.isProcessed = true;
            enqueueNextJobIfAny();
            return;
        }
        resultWriter.stampSalesforceJobId(nextJob);
    }

    public void stop() {
        isStopped = true;
        for (QueueableJob job : jobs) {
            if (!job.isProcessed) {
                markSkipped(
                    job,
                    QueueableManager.STATUS_SKIPPED_CHAIN_STOPPED,
                    chainStopReason(job)
                );
            }
        }
    }

    private String chainStopReason(QueueableJob job) {
        String reason = 'Chain stopped via Async.stopChain().';
        return isChunkPageThatNeverStarted(job)
            ? reason + ' ' + ((ChunkJob) job).getRun().remainingWorkSummary()
            : reason;
    }

    private Boolean isChunkPageThatNeverStarted(QueueableJob job) {
        return job instanceof ChunkJob && job.customJobId != currentJob?.customJobId;
    }

    public void skipJobByCustomJobId(String customJobId) {
        if (!hasJob(customJobId)) {
            throw new IllegalArgumentException(
                String.format(
                    QueueableManager.ERROR_MESSAGE_UNKNOWN_JOB,
                    new List<String>{ customJobId }
                )
            );
        }
        Set<String> customJobIdsToSkip = getAllCustomJobIdsToRemove(new Set<String>{ customJobId });
        for (QueueableJob job : jobs) {
            if (customJobIdsToSkip.contains(job.customJobId) && !job.isProcessed) {
                markSkipped(
                    job,
                    QueueableManager.STATUS_SKIPPED_EXPLICIT,
                    'Skipped via Async.skipJob().'
                );
            }
        }
    }

    private Boolean hasJob(String customJobId) {
        for (QueueableJob job : jobs) {
            if (job.customJobId == customJobId) {
                return true;
            }
        }
        return false;
    }

    private void markSkipped(QueueableJob job, String status, String reason) {
        job.isProcessed = true;
        job.skipStatus = status;
        job.skipReason = reason;
    }

    private void skipJobsWithUnsatisfiedDependencies() {
        QueueableJob candidate = getNextJobToProcess();
        while (
            candidate != null &&
            QueueableManager.firstUnsatisfiedDependency(candidate, outcomeByCustomJobId) != null
        ) {
            markSkipped(
                candidate,
                QueueableManager.STATUS_SKIPPED_DEPENDENCY,
                buildDependencySkipReason(candidate)
            );
            candidate = getNextJobToProcess();
        }
    }

    private String buildDependencySkipReason(QueueableJob job) {
        Async.Dependency blocking = QueueableManager.firstUnsatisfiedDependency(
            job,
            outcomeByCustomJobId
        );
        Async.Outcome actual = outcomeByCustomJobId.get(blocking.resolvedTargetCustomJobId);
        return 'Dependency \'' +
            labelForCustomJobId(blocking.resolvedTargetCustomJobId) +
            '\' required ' +
            blocking.requiredOutcome.name() +
            ' but was ' +
            (actual?.name() ?? 'NOT_RUN');
    }

    private String labelForCustomJobId(String customJobId) {
        for (QueueableJob job : jobs) {
            if (job.customJobId == customJobId) {
                return job.className;
            }
        }
        return customJobId;
    }

    public Boolean hasNextJob() {
        return getNextJobToProcess() != null;
    }

    public void addJob(QueueableJob job) {
        chainName = job.chainName ?? chainName;
        for (QueueableJob queued : jobs) {
            queued.chainName = chainName;
        }
        job.chainName = chainName;
        AsyncRequeue.captureJobAsHandedOver(job);
        job.setMainAttributes();
        if (chainId == null) {
            chainId = UUID.randomUUID().toString();
        }
        job.chainId = chainId;
        keepSlotOfChunkRunOrTakeNextOne(job);
        placeNextInChainIfRequested(job);
        QueueableJobSettings.applyRetryDefaults(job);
        QueueableManager.assertStateHandlingDeclared(job);
        job.captureEnqueuedState();
        jobs.add(job);
        jobs.sort();
        keepSequenceInRunOrder();
        AsyncEventDispatcher.jobEnqueued(job, QueueableManager.loggerClassFor(job));
    }

    private void keepSequenceInRunOrder() {
        List<QueueableJob> waitingInRunOrder = new List<QueueableJob>();
        List<Integer> slots = new List<Integer>();
        for (QueueableJob queued : jobs) {
            if (ownsAMovableSlot(queued)) {
                waitingInRunOrder.add(queued);
                slots.add(queued.chainSequence);
            }
        }
        slots.sort();
        for (Integer i = 0; i < slots.size(); i++) {
            QueueableJob waiting = waitingInRunOrder[i];
            if (waiting.chainSequence != slots[i]) {
                waiting.chainSequence = slots[i];
                resultWriter.markResequenced(waiting.customJobId);
            }
        }
    }

    private Boolean ownsAMovableSlot(QueueableJob job) {
        return !job.isProcessed &&
            !job.isFinalizer &&
            job.customJobId != currentJob?.customJobId &&
            !isLaterPageOfChunkRun(job);
    }

    private Boolean isLaterPageOfChunkRun(QueueableJob job) {
        return job instanceof ChunkJob && ((ChunkJob) job).getRun().currentPageNumber() > 1;
    }

    private void keepSlotOfChunkRunOrTakeNextOne(QueueableJob job) {
        job.chainSequence = job.chainSequence ?? ++jobSequence;
        if (job instanceof ChunkJob) {
            ChunkRun run = ((ChunkJob) job).getRun();
            run.runId = run.runId ?? job.customJobId;
        }
    }

    private void placeNextInChainIfRequested(QueueableJob job) {
        if (job.nextInChain != true) {
            return;
        }
        if (currentJob == null) {
            throw new IllegalArgumentException(
                QueueableManager.ERROR_MESSAGE_NEXT_IN_CHAIN_OUTSIDE_CHAIN
            );
        }
        nextInChainSlot++;
        for (QueueableJob queued : jobs) {
            if (
                !queued.isProcessed &&
                !queued.isFinalizer &&
                queued.chainSequence >= nextInChainSlot
            ) {
                queued.chainSequence++;
                resultWriter.markResequenced(queued.customJobId);
            }
        }
        job.chainSequence = nextInChainSlot;
    }

    public List<QueueableJob> getJobs() {
        return jobs;
    }

    public void executeOrReplaceInitialQueueableChainSchedulableJob() {
        QueueableChainSchedulable.removeInitialQueuableChainSchedulableIfExists(
            initialQueuableChainSchedulableId
        );

        Datetime nextRunTime = Datetime.now().addMinutes(1);
        String hour = String.valueOf(nextRunTime.hour());
        String min = String.valueOf(nextRunTime.minute());
        String ss = String.valueOf(nextRunTime.second());
        String nextFireTime = ss + ' ' + min + ' ' + hour + ' * * ?';

        initialQueuableChainSchedulableId = System.schedule(
            'QueueableChainSchedulable/' +
                String.valueOf(Datetime.now()) +
                '/' +
                UUID.randomUUID().toString(),
            nextFireTime,
            new QueueableChainSchedulable(this)
        );
    }

    public QueueableJob getCurrentJob() {
        return currentJob;
    }

    public Boolean isChainedContext() {
        return isChainedContext;
    }

    public Id getQueueableChainSchedulableId() {
        return initialQueuableChainSchedulableId;
    }

    @TestVisible
    private void removeJobsThatAreDisabledAndDependentFinalizers() {
        if (QueueableJobSettings.jobSettingByName.isEmpty()) {
            return;
        }
        if (QueueableJobSettings.forAllJobs()?.IsDisabled__c == true) {
            markDisabledAndRecord(new List<QueueableJob>(jobs));
            jobs.clear();
            return;
        }

        Set<String> customJobIdsToRemove = new Set<String>();
        for (QueueableJob job : jobs) {
            if (QueueableJobSettings.isDisabled(job)) {
                customJobIdsToRemove.add(job.customJobId);
            }
        }

        if (customJobIdsToRemove.isEmpty()) {
            return;
        }
        customJobIdsToRemove = getAllCustomJobIdsToRemove(customJobIdsToRemove);

        List<QueueableJob> disabledJobs = new List<QueueableJob>();
        for (QueueableJob job : jobs) {
            if (customJobIdsToRemove.contains(job.customJobId)) {
                disabledJobs.add(job);
            }
        }
        markDisabledAndRecord(disabledJobs);

        for (Integer i = jobs.size() - 1; i >= 0; i--) {
            if (customJobIdsToRemove.contains(jobs[i].customJobId)) {
                jobs.remove(i);
            }
        }
    }

    private void markDisabledAndRecord(List<QueueableJob> disabledJobs) {
        for (QueueableJob job : disabledJobs) {
            if (!job.isProcessed) {
                markSkipped(
                    job,
                    QueueableManager.STATUS_SKIPPED_DISABLED,
                    'Disabled via QueueableJobSetting__mdt.'
                );
            }
        }
        resultWriter.recordResults(disabledJobs, outcomeByCustomJobId);
    }

    private Set<String> getAllCustomJobIdsToRemove(Set<String> customJobIdsToRemove) {
        Set<String> dependentCustomJobIdsToRemove = new Set<String>();
        for (QueueableJob job : jobs) {
            if (customJobIdsToRemove.contains(job.parentCustomJobId)) {
                dependentCustomJobIdsToRemove.add(job.customJobId);
            }
        }

        if (dependentCustomJobIdsToRemove.isEmpty()) {
            return customJobIdsToRemove;
        } else {
            customJobIdsToRemove.addAll(getAllCustomJobIdsToRemove(dependentCustomJobIdsToRemove));
            return customJobIdsToRemove;
        }
    }

    private QueueableJob getNextJobToProcess() {
        for (QueueableJob job : jobs) {
            if (!job.isProcessed) {
                return job;
            }
        }
        return null;
    }

    private void setFinalizerContextToAllFinalizersForPreviousJob(
        QueueableJob previousJob,
        FinalizerContext ctx
    ) {
        for (QueueableJob job : jobs) {
            if (
                !job.isProcessed &&
                job.parentCustomJobId == previousJob.customJobId &&
                job.finalizerCtx == null
            ) {
                injectFinalizerMockOrDefault(job, ctx);
            }
        }
    }

    private void injectQueueableMockIfNeeded(QueueableJob job) {
        if (!Test.isRunningTest() || !AsyncMock.hasQueueableMock(job.mockId)) {
            return;
        }
        QueueableContext ctx = AsyncMock.getQueueableContext(job.mockId);
        job.queueableCtx = ctx;
        Exception mockedFailure = ctx instanceof AsyncMock.MockQueueableContext
            ? ((AsyncMock.MockQueueableContext) ctx).getException()
            : null;
        if (mockedFailure != null) {
            throw mockedFailure;
        }
    }

    private void injectFinalizerMockOrDefault(QueueableJob job, FinalizerContext defaultCtx) {
        if (Test.isRunningTest() && AsyncMock.hasFinalizerMock(job.mockId)) {
            job.finalizerCtx = AsyncMock.getFinalizerContext(job.mockId);
            return;
        }
        job.finalizerCtx = defaultCtx;
    }
}
