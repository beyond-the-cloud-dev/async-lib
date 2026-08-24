/**
 * PMD False Positives:
 * - CognitiveComplexity: This was intended to have all the logic in one class
 **/
@SuppressWarnings('PMD.CognitiveComplexity')
public inherited sharing class QueueableChain {
    @TestVisible
    private List<QueueableJob> jobs = new List<QueueableJob>();
    @TestVisible
    private Id initialQueuableChainSchedulableId;
    private Boolean isChainedContext = false;
    private Boolean isStopped = false;
    private Integer chainCounter = 0;
    private Integer jobSequence = 0;
    private QueueableJob currentJob;
    private Map<String, Async.Outcome> outcomeByCustomJobId = new Map<String, Async.Outcome>();
    private Map<String, Id> resultIdByCustomJobId = new Map<String, Id>();
    private String chainId;

    @TestVisible
    private Map<String, QueueableJobSetting__mdt> queueableJobSettingByJobName {
        get {
            if (Test.isRunningTest()) {
                return queueableJobSettingByJobName ?? new Map<String, QueueableJobSetting__mdt>();
            }
            Map<String, QueueableJobSetting__mdt> jobSettings = new Map<String, QueueableJobSetting__mdt>();
            for (QueueableJobSetting__mdt jobSetting : QueueableJobSetting__mdt.getAll().values()) {
                jobSettings.put(jobSetting.QueueableJobName__c, jobSetting);
            }
            return jobSettings;
        }
        private set;
    }

    public void execute(QueueableContext ctx) {
        QueueableManager.get().setChain(this);
        attachQueueableChainFinalizer();
        executeCurrentJob(ctx);
    }

    public void attachQueueableChainFinalizer() {
        System.attachFinalizer(new QueueableChainFinalizer(this));
    }

    public void executeCurrentJob(QueueableContext ctx) {
        if (!hasNextJob()) {
            return;
        }

        currentJob = getNextJobToProcess();
        currentJob.queueableCtx = ctx;
        currentJob.salesforceJobId = ctx.getJobId();
        currentJob.setChainCounterToName(++chainCounter);

        Savepoint sp = currentJob.rollbackOnJobExecuteFail ? Database.setSavepoint() : null;
        try {
            // Debug statements to determine the Job Id and Name
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

        if (previousJob.canRetry()) {
            enqueueRetry(previousJob);
            return;
        }

        if (previousJob.hasFailed && previousJob.maxRetries > 0) {
            previousJob.recordRetryHistory(previousJob.retryAttempt + 1, null);
        }

        previousJob.isProcessed = true;
        previousJob.finalizerCtx = ctx;
        recordOutcome(previousJob);

        setFinalizerContextToAllFinalizersForPreviousJob(previousJob, ctx);
        maybeAdvanceChunkRun(previousJob);
        enqueueNextJobIfAny();
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
                resultIdByCustomJobId.remove(job.customJobId);
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

    private void recordChunkRunOutcome(ChunkJob settledPage) {
        ChunkRun run = settledPage.getRun();
        Boolean anyPageFailed = run.hasFailedPage || settledPage.hasFailed;
        outcomeByCustomJobId.put(
            run.runId,
            anyPageFailed ? Async.Outcome.FAILURE : Async.Outcome.SUCCESS
        );
    }

    private void enqueueRetry(QueueableJob previousJob) {
        Integer nextAttempt = previousJob.retryAttempt + 1;
        Integer delayMinutes = previousJob.backoff?.delayMinutes(nextAttempt);

        previousJob.recordRetryHistory(nextAttempt, delayMinutes);
        previousJob.isProcessed = true;
        // Only the final attempt produces a result row; suppress this superseded one.
        previousJob.resultCreated = true;

        QueueableJob retryJob = previousJob.cloneJob();
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
        retryJob.resetForRetry();

        jobs.add(0, retryJob);
        enqueueNextJobIfAny();
    }

    private Boolean resultEnabledFor(QueueableJob job) {
        return queueableJobSettingByJobName.get(QueueableManager.QUEUEABLE_JOB_SETTING_ALL)
                ?.CreateResult__c == true ||
            queueableJobSettingByJobName.get(job.className)?.CreateResult__c == true;
    }

    private void createPendingResults() {
        List<QueueableJob> candidates = new List<QueueableJob>();
        for (QueueableJob job : jobs) {
            if (job.isProcessed && !job.resultCreated) {
                candidates.add(job);
            }
        }
        recordResults(candidates);
    }

    private void recordResults(List<QueueableJob> candidates) {
        List<QueueableJob> toRecord = new List<QueueableJob>();
        for (QueueableJob job : candidates) {
            if (job.resultCreated) {
                continue;
            }
            if (resultEnabledFor(job)) {
                toRecord.add(job);
            } else {
                job.resultCreated = true;
            }
        }
        if (toRecord.isEmpty()) {
            return;
        }

        List<AsyncResult__c> results = new List<AsyncResult__c>();
        for (QueueableJob job : toRecord) {
            results.add(buildResult(job));
        }
        insert results;
        for (Integer i = 0; i < toRecord.size(); i++) {
            toRecord[i].resultCreated = true;
            resultIdByCustomJobId.put(toRecord[i].customJobId, results[i].Id);
        }
        linkDependencyResults(toRecord);
    }

    private AsyncResult__c buildResult(QueueableJob job) {
        AsyncResult__c result = new AsyncResult__c(
            SalesforceJobId__c = job.salesforceJobId,
            CustomJobId__c = job.customJobId,
            ChainId__c = job.chainId,
            ClassName__c = job.className,
            RetryAttempts__c = job.retryAttempt,
            RetryHistory__c = job.retryHistory
        );
        if (job.skipStatus != null) {
            result.Status__c = job.skipStatus;
            result.SkipReason__c = job.skipReason;
        } else if (job.hasFailed) {
            result.Status__c = QueueableManager.STATUS_FAILED;
            result.Result__c = job.finalizerCtx?.getResult()?.name();
            result.ExceptionType__c = job.failure?.type;
            result.ExceptionMessage__c = job.failure?.message;
        } else {
            result.Status__c = QueueableManager.STATUS_COMPLETED;
            result.Result__c = job.finalizerCtx?.getResult()?.name();
        }
        return result;
    }

    private void linkDependencyResults(List<QueueableJob> recordedJobs) {
        List<AsyncResult__c> toUpdate = new List<AsyncResult__c>();
        for (QueueableJob job : recordedJobs) {
            Async.Dependency decisive = decisiveDependency(job);
            Id dependencyResultId = decisive == null
                ? null
                : resultIdByCustomJobId.get(decisive.resolvedTargetCustomJobId);
            if (dependencyResultId == null) {
                continue;
            }
            Async.Outcome actual = outcomeByCustomJobId.get(decisive.resolvedTargetCustomJobId);
            toUpdate.add(
                new AsyncResult__c(
                    Id = resultIdByCustomJobId.get(job.customJobId),
                    DependsOnResult__c = dependencyResultId,
                    RequiredOutcome__c = decisive.requiredOutcome.name(),
                    ActualOutcome__c = actual != null ? actual.name() : 'NOT_RUN'
                )
            );
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    private Async.Dependency decisiveDependency(QueueableJob job) {
        if (job.dependencies == null || job.dependencies.isEmpty()) {
            return null;
        }
        Async.Dependency blocking = firstUnsatisfiedDependency(job);
        return blocking != null ? blocking : job.dependencies[0];
    }

    public void enqueueNextJobIfAny() {
        removeJobsThatAreDisabledAndDependentFinalizers();
        skipJobsWithUnsatisfiedDependencies();
        createPendingResults();
        if (!hasNextJob() || (Test.isRunningTest() && System.isQueueable())) {
            return;
        }

        QueueableJob nextJob = getNextJobToProcess();
        try {
            isChainedContext = true;
            nextJob.enqueue(this);
        } catch (Exception ex) {
            if (!nextJob.continueOnJobEnqueueFail) {
                throw ex;
            }
            isChainedContext = false;
            nextJob.isProcessed = true;
            enqueueNextJobIfAny();
        }
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
        while (candidate != null && firstUnsatisfiedDependency(candidate) != null) {
            markSkipped(
                candidate,
                QueueableManager.STATUS_SKIPPED_DEPENDENCY,
                buildDependencySkipReason(candidate)
            );
            candidate = getNextJobToProcess();
        }
    }

    private Async.Dependency firstUnsatisfiedDependency(QueueableJob job) {
        if (job.dependencies == null) {
            return null;
        }
        for (Async.Dependency dependency : job.dependencies) {
            Async.Outcome actual = outcomeByCustomJobId.get(dependency.resolvedTargetCustomJobId);
            if (!outcomeMatches(actual, dependency.requiredOutcome)) {
                return dependency;
            }
        }
        return null;
    }

    private String buildDependencySkipReason(QueueableJob job) {
        Async.Dependency blocking = firstUnsatisfiedDependency(job);
        Async.Outcome actual = outcomeByCustomJobId.get(blocking.resolvedTargetCustomJobId);
        return 'Dependency \'' +
            labelForCustomJobId(blocking.resolvedTargetCustomJobId) +
            '\' required ' +
            blocking.requiredOutcome.name() +
            ' but was ' +
            (actual != null ? actual.name() : 'NOT_RUN');
    }

    private String labelForCustomJobId(String customJobId) {
        for (QueueableJob job : jobs) {
            if (job.customJobId == customJobId) {
                return job.className;
            }
        }
        return customJobId;
    }

    private Boolean outcomeMatches(Async.Outcome actual, Async.Outcome required) {
        if (actual == null) {
            return false;
        }
        return required == Async.Outcome.COMPLETED || actual == required;
    }

    public Boolean hasNextJob() {
        return getNextJobToProcess() != null;
    }

    public void addJob(QueueableJob job) {
        job.setMainAttributes();
        if (chainId == null) {
            chainId = UUID.randomUUID().toString();
        }
        job.chainId = chainId;
        keepSlotOfChunkRunOrTakeNextOne(job);
        applyRetryDefaultsIfNeeded(job);
        jobs.add(job);
        jobs.sort();
    }

    private void keepSlotOfChunkRunOrTakeNextOne(QueueableJob job) {
        job.chainSequence = job.chainSequence ?? ++jobSequence;
        if (job instanceof ChunkJob) {
            ChunkRun run = ((ChunkJob) job).getRun();
            run.runId = run.runId ?? job.customJobId;
        }
    }

    @TestVisible
    private void applyRetryDefaultsIfNeeded(QueueableJob job) {
        if (job.maxRetries > 0) {
            // Explicit fluent .retry(...) wins over CMDT defaults.
            return;
        }

        QueueableJobSetting__mdt setting = resolveRetrySetting(job.className);
        if (setting == null) {
            return;
        }

        Integer settingMaxRetries = setting.MaxRetries__c.intValue();
        if (settingMaxRetries > QueueableManager.MAX_RETRY_CAP) {
            throw new IllegalArgumentException(
                QueueableManager.ERROR_MESSAGE_MAX_RETRIES_EXCEEDS_CAP
            );
        }
        job.maxRetries = settingMaxRetries;

        if (job.backoff == null && String.isNotBlank(setting.BackoffStrategy__c)) {
            Integer baseMinutes = setting.BackoffBaseMinutes__c?.intValue() ?? 1;
            job.backoff = Backoff.fromName(setting.BackoffStrategy__c, baseMinutes);
        }

        if (job.retryOnExceptionTypes == null) {
            job.retryOnExceptionTypes = parseExceptionTypes(setting.RetryableExceptions__c);
        }
    }

    private QueueableJobSetting__mdt resolveRetrySetting(String jobClassName) {
        Map<String, QueueableJobSetting__mdt> jobSettings = queueableJobSettingByJobName;
        QueueableJobSetting__mdt setting = jobSettings.get(jobClassName);
        if (setting == null || setting.MaxRetries__c == null) {
            setting = jobSettings.get(QueueableManager.QUEUEABLE_JOB_SETTING_ALL);
        }
        Boolean hasRetryDefault =
            setting != null &&
            setting.MaxRetries__c != null &&
            setting.MaxRetries__c > 0;
        return hasRetryDefault ? setting : null;
    }

    private Set<String> parseExceptionTypes(String csv) {
        if (String.isBlank(csv)) {
            return null;
        }
        Set<String> types = new Set<String>();
        for (String exceptionType : csv.split(',')) {
            if (String.isNotBlank(exceptionType)) {
                types.add(exceptionType.trim());
            }
        }
        return types.isEmpty() ? null : types;
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
        Map<String, QueueableJobSetting__mdt> jobSettings = queueableJobSettingByJobName;

        if (jobSettings.isEmpty()) {
            // If there are no job settings, do not remove any jobs
            return;
        }

        QueueableJobSetting__mdt allJobSetting = jobSettings.get(
            QueueableManager.QUEUEABLE_JOB_SETTING_ALL
        );

        if (allJobSetting?.IsDisabled__c == true) {
            // If the global setting is disabled, clear all jobs
            markDisabledAndRecord(new List<QueueableJob>(jobs));
            jobs.clear();
            return;
        }

        // there are job settings, and if the class is disabled it should be removed and if there is a finalizer that have parentJobId set to this removed job, it should be removed as well, think about creating some logical way to do that, maybe recursion
        Set<String> customJobIdsToRemove = new Set<String>();
        for (QueueableJob job : jobs) {
            QueueableJobSetting__mdt jobSetting = jobSettings.get(job.className);
            if (jobSetting != null && jobSetting.IsDisabled__c) {
                customJobIdsToRemove.add(job.customJobId);
            }
        }

        // If there are no jobs to remove, return early
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
        recordResults(disabledJobs);
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
