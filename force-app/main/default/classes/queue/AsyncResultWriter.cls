/**
 * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
 *
 * v3.2.0
 *
 * PMD False Positives:
 * - CognitiveComplexity / CyclomaticComplexity: one guard clause per write path, and the most
 *   complex member scores 8
 * - AvoidDebugStatements: when the framework failure row cannot be written either, the debug log
 *   is the only channel left
 **/
@SuppressWarnings('PMD.CognitiveComplexity,PMD.CyclomaticComplexity')
public inherited sharing class AsyncResultWriter {
    @TestVisible
    private static Integer dmlRowReserve = 200;
    private Map<String, Id> resultIdByCustomJobId = new Map<String, Id>();
    private Set<String> resequencedCustomJobIds = new Set<String>();

    public void forget(String customJobId) {
        resultIdByCustomJobId.remove(customJobId);
    }

    public void markResequenced(String customJobId) {
        resequencedCustomJobIds.add(customJobId);
    }

    @SuppressWarnings('PMD.AvoidDebugStatements')
    public void recordFrameworkFailure(
        String chainId,
        QueueableJob currentJob,
        Exception frameworkFailure
    ) {
        try {
            insert as system new AsyncResult__c(
                ChainId__c = chainId,
                CustomJobId__c = currentJob?.customJobId,
                ClassName__c = currentJob?.className,
                SalesforceJobId__c = currentJob?.salesforceJobId,
                Status__c = QueueableManager.STATUS_FRAMEWORK_ERROR,
                ExceptionType__c = frameworkFailure.getTypeName(),
                ExceptionMessage__c = QueueableManager.frameworkFailureMessage(frameworkFailure)
            );
        } catch (Exception recordingFailure) {
            System.debug(
                LoggingLevel.ERROR,
                QueueableManager.frameworkFailureMessage(frameworkFailure) +
                    '\nThe failure could not be recorded either: ' +
                    recordingFailure.getMessage()
            );
        }
    }

    public void recordResults(
        List<QueueableJob> candidates,
        Map<String, Async.Outcome> outcomeByCustomJobId
    ) {
        List<QueueableJob> toRecord = new List<QueueableJob>();
        for (QueueableJob job : candidates) {
            if (job.resultCreated) {
                continue;
            }
            if (resultEnabledFor(job)) {
                toRecord.add(job);
            } else {
                job.resultCreated = true;
                AsyncRequeue.releasePayload(job);
            }
        }
        if (toRecord.isEmpty()) {
            return;
        }

        List<AsyncResult__c> toInsert = new List<AsyncResult__c>();
        List<AsyncResult__c> toUpdate = new List<AsyncResult__c>();
        List<QueueableJob> inserted = new List<QueueableJob>();
        List<QueueableJob> updated = new List<QueueableJob>();
        Integer linkRoom = recordLinkRoomFor(toRecord.size());
        for (QueueableJob job : toRecord) {
            applyRecordLinkCap(job);
            linkRoom -= applyDmlRowBudget(job, linkRoom);
            AsyncResult__c result = buildResult(job);
            if (result.Id == null) {
                toInsert.add(result);
                inserted.add(job);
            } else {
                toUpdate.add(result);
                updated.add(job);
            }
        }
        List<AsyncResult__c> all = new List<AsyncResult__c>(toInsert);
        all.addAll(toUpdate);
        dropLinksToSourcesTheCleanupBatchRemoved(all);
        insert as system toInsert;
        for (Integer i = 0; i < inserted.size(); i++) {
            resultIdByCustomJobId.put(inserted[i].customJobId, toInsert[i].Id);
        }
        updateOrReplacePlaceholders(toUpdate, updated);
        for (QueueableJob job : toRecord) {
            job.resultCreated = true;
            AsyncRequeue.releasePayload(job);
        }
        writeRecordLinks(toRecord);
        linkDependencyResults(toRecord, outcomeByCustomJobId);
    }

    private Boolean resultEnabledFor(QueueableJob job) {
        return QueueableJobSettings.createResultEnabledFor(job) ||
            payloadStorageOnAndJobDidNotSucceed(job) ||
            QueueableManager.trackProgressEnabledFor(job) ||
            hasRecordLinks(job);
    }

    private Boolean hasRecordLinks(QueueableJob job) {
        return (job.recordLinksWritten ?? 0) > 0 || (job.links != null && !job.links.isEmpty());
    }

    private Boolean payloadStorageOnAndJobDidNotSucceed(QueueableJob job) {
        return job.requeueStatus != null && (job.hasFailed || job.skipStatus != null);
    }

    private void updateOrReplacePlaceholders(
        List<AsyncResult__c> toUpdate,
        List<QueueableJob> updated
    ) {
        List<Database.SaveResult> outcomes = Database.update(
            toUpdate,
            false,
            AccessLevel.SYSTEM_MODE
        );
        List<AsyncResult__c> replacements = new List<AsyncResult__c>();
        List<QueueableJob> replaced = new List<QueueableJob>();
        for (Integer i = 0; i < outcomes.size(); i++) {
            if (outcomes[i].isSuccess()) {
                continue;
            }
            QueueableJob job = updated[i];
            job.recordConfigurationWarning(
                String.format(
                    QueueableManager.WARNING_PROGRESS_ROW_REPLACED,
                    new List<String>{ job.className, outcomes[i].getErrors()[0].getMessage() }
                )
            );
            resultIdByCustomJobId.remove(job.customJobId);
            job.recordLinksWritten = 0;
            replacements.add(buildResult(job));
            replaced.add(job);
        }
        if (replacements.isEmpty()) {
            return;
        }
        dropLinksToSourcesTheCleanupBatchRemoved(replacements);
        insert as system replacements;
        for (Integer i = 0; i < replaced.size(); i++) {
            resultIdByCustomJobId.put(replaced[i].customJobId, replacements[i].Id);
        }
    }

    public void createEnqueuedPlaceholders(List<QueueableJob> jobs, QueueableJob currentJob) {
        resequencePlaceholders(jobs, currentJob);
        List<QueueableJob> pending = new List<QueueableJob>();
        for (QueueableJob job : jobs) {
            if (
                !job.isProcessed &&
                !resultIdByCustomJobId.containsKey(job.customJobId) &&
                QueueableManager.trackProgressEnabledFor(job)
            ) {
                pending.add(job);
            }
        }
        if (pending.isEmpty()) {
            return;
        }
        List<AsyncResult__c> rows = new List<AsyncResult__c>();
        Integer linkRoom = recordLinkRoomFor(pending.size());
        for (QueueableJob job : pending) {
            applyRecordLinkCap(job);
            linkRoom -= applyDmlRowBudget(job, linkRoom);
            AsyncResult__c row = identityOf(job);
            row.Status__c = QueueableManager.STATUS_ENQUEUED;
            rows.add(row);
        }
        try {
            insert as system rows;
        } catch (Exception writeFailure) {
            recordProgressRowNotWritten(pending[0], writeFailure);
            return;
        }
        for (Integer i = 0; i < pending.size(); i++) {
            resultIdByCustomJobId.put(pending[i].customJobId, rows[i].Id);
        }
        writeRecordLinks(pending);
    }

    private void resequencePlaceholders(List<QueueableJob> jobs, QueueableJob currentJob) {
        List<AsyncResult__c> moved = new List<AsyncResult__c>();
        for (QueueableJob job : jobs) {
            Id placeholderId = resultIdByCustomJobId.get(job.customJobId);
            if (placeholderId != null && resequencedCustomJobIds.contains(job.customJobId)) {
                moved.add(
                    new AsyncResult__c(Id = placeholderId, ChainSequence__c = job.chainSequence)
                );
            }
        }
        resequencedCustomJobIds.clear();
        if (moved.isEmpty()) {
            return;
        }
        try {
            update as system moved;
        } catch (Exception writeFailure) {
            recordProgressRowNotWritten(currentJob ?? jobs[0], writeFailure);
        }
    }

    public void deletePlaceholdersOfUnprocessedJobs(
        List<QueueableJob> jobs,
        QueueableJob failedJob
    ) {
        List<AsyncResult__c> placeholders = new List<AsyncResult__c>();
        for (QueueableJob job : jobs) {
            Id placeholderId = resultIdByCustomJobId.get(job.customJobId);
            if (!job.isProcessed && placeholderId != null) {
                placeholders.add(new AsyncResult__c(Id = placeholderId));
                resultIdByCustomJobId.remove(job.customJobId);
                job.recordLinksWritten = 0;
            }
        }
        try {
            delete as system placeholders;
        } catch (Exception deleteFailure) {
            recordProgressRowNotWritten(failedJob, deleteFailure);
        }
    }

    public void stampSalesforceJobId(QueueableJob enqueuedJob) {
        Id placeholderId = resultIdByCustomJobId.get(enqueuedJob.customJobId);
        if (placeholderId == null || enqueuedJob.salesforceJobId == null) {
            return;
        }
        AsyncResult__c stamped = new AsyncResult__c(
            Id = placeholderId,
            SalesforceJobId__c = enqueuedJob.salesforceJobId
        );
        Integer delayMinutes = delayMinutesOf(enqueuedJob);
        if (enqueuedJob.retryAttempt == 0 && delayMinutes > 0) {
            stamped.NextAttemptAt__c = System.now().addMinutes(delayMinutes);
        }
        try {
            update as system stamped;
        } catch (Exception writeFailure) {
            recordProgressRowNotWritten(enqueuedJob, writeFailure);
        }
    }

    public void updatePlaceholderForRetry(
        QueueableJob previousJob,
        Integer nextAttempt,
        Integer delayMinutes
    ) {
        Id placeholderId = resultIdByCustomJobId.get(previousJob.customJobId);
        if (placeholderId == null) {
            return;
        }
        try {
            update as system new AsyncResult__c(
                Id = placeholderId,
                RetryAttempts__c = nextAttempt,
                RetryHistory__c = previousJob.retryHistory,
                NextAttemptAt__c = System.now().addMinutes(delayMinutes ?? 0)
            );
        } catch (Exception writeFailure) {
            recordProgressRowNotWritten(previousJob, writeFailure);
        }
    }

    private Integer delayMinutesOf(QueueableJob job) {
        return job.delay ?? job.asyncOptions?.MinimumQueueableDelayInMinutes ?? 0;
    }

    private void recordProgressRowNotWritten(QueueableJob job, Exception writeFailure) {
        job.recordConfigurationWarning(
            String.format(
                QueueableManager.WARNING_PROGRESS_ROW_NOT_WRITTEN,
                new List<String>{ job.className, writeFailure.getMessage() }
            )
        );
    }

    private void applyRecordLinkCap(QueueableJob job) {
        if (job.links == null) {
            return;
        }
        Integer written = job.recordLinksWritten ?? 0;
        Integer allowed = QueueableManager.maxRecordLinksFor(job) - written;
        if (job.links.size() <= allowed) {
            return;
        }
        job.recordConfigurationWarning(
            String.format(
                QueueableManager.WARNING_RECORD_LINKS_TRUNCATED,
                new List<String>{
                    String.valueOf(allowed + written),
                    job.className,
                    String.valueOf(written + job.links.size())
                }
            )
        );
        job.links = firstOf(job.links, allowed);
    }

    private Integer recordLinkRoomFor(Integer resultRows) {
        return Limits.getLimitDmlRows() - Limits.getDmlRows() - dmlRowReserve - resultRows;
    }

    private Integer applyDmlRowBudget(QueueableJob job, Integer room) {
        if (job.links == null || job.links.isEmpty()) {
            return 0;
        }
        Integer stored = Math.min(Math.max(room, 0), job.links.size());
        if (stored == job.links.size()) {
            return stored;
        }
        job.recordConfigurationWarning(
            String.format(
                QueueableManager.WARNING_RECORD_LINKS_DML_BUDGET,
                new List<String>{
                    String.valueOf(stored),
                    String.valueOf(job.links.size()),
                    job.className
                }
            )
        );
        job.links = firstOf(job.links, stored);
        return stored;
    }

    private static List<Async.RecordLink> firstOf(List<Async.RecordLink> links, Integer count) {
        List<Async.RecordLink> kept = new List<Async.RecordLink>();
        for (Integer i = 0; i < Math.max(count, 0); i++) {
            kept.add(links[i]);
        }
        return kept;
    }

    private void writeRecordLinks(List<QueueableJob> recordedJobs) {
        List<AsyncResultLink__c> rows = new List<AsyncResultLink__c>();
        List<QueueableJob> owners = new List<QueueableJob>();
        for (QueueableJob job : recordedJobs) {
            Id resultId = resultIdByCustomJobId.get(job.customJobId);
            if (resultId == null || job.links == null || job.links.isEmpty()) {
                continue;
            }
            for (Async.RecordLink link : job.links) {
                rows.add(
                    new AsyncResultLink__c(
                        AsyncResult__c = resultId,
                        Key__c = link.key,
                        Source__c = link.source,
                        ObjectName__c = link.objectName,
                        UniqueKey__c = uniqueKeyOf(resultId, link)
                    )
                );
                owners.add(job);
            }
            job.recordLinksWritten = (job.recordLinksWritten ?? 0) + job.links.size();
            job.links = null;
        }
        if (rows.isEmpty()) {
            return;
        }
        List<Database.SaveResult> outcomes = Database.insert(rows, false, AccessLevel.SYSTEM_MODE);
        for (Integer i = 0; i < outcomes.size(); i++) {
            if (outcomes[i].isSuccess()) {
                continue;
            }
            Database.Error error = outcomes[i].getErrors()[0];
            owners[i].recordLinksWritten--;
            if (error.getStatusCode() == StatusCode.DUPLICATE_VALUE) {
                continue;
            }
            owners[i]
                .recordConfigurationWarning(
                    String.format(
                        QueueableManager.WARNING_RECORD_LINKS_NOT_WRITTEN,
                        new List<String>{ owners[i].className, error.getMessage() }
                    )
                );
        }
    }

    private static String uniqueKeyOf(Id resultId, Async.RecordLink link) {
        Blob identity = Blob.valueOf(QueueableManager.linkIdentityOf(link));
        return resultId + ':' + EncodingUtil.convertToHex(Crypto.generateDigest('SHA1', identity));
    }

    private void dropLinksToSourcesTheCleanupBatchRemoved(List<AsyncResult__c> results) {
        Set<Id> sourceIds = new Set<Id>();
        for (AsyncResult__c result : results) {
            if (result.RequeuedFrom__c != null) {
                sourceIds.add(result.RequeuedFrom__c);
            }
        }
        if (sourceIds.isEmpty()) {
            return;
        }
        Set<Id> stillThere = new Map<Id, AsyncResult__c>(
                [SELECT Id FROM AsyncResult__c WHERE Id IN :sourceIds WITH SYSTEM_MODE]
            )
            .keySet();
        for (AsyncResult__c result : results) {
            if (result.RequeuedFrom__c != null && !stillThere.contains(result.RequeuedFrom__c)) {
                result.RequeuedFrom__c = null;
            }
        }
    }

    private AsyncResult__c identityOf(QueueableJob job) {
        AsyncResult__c row = new AsyncResult__c(
            SalesforceJobId__c = job.salesforceJobId,
            CustomJobId__c = job.customJobId,
            ChainId__c = job.chainId,
            ClassName__c = job.className,
            JobName__c = job.jobName,
            ChainName__c = job.chainName,
            ChainSequence__c = job.chainSequence,
            Priority__c = job.priority,
            ParentCustomJobId__c = job.parentCustomJobId,
            AddedByCustomJobId__c = job.addedByCustomJobId,
            Dependencies__c = job.dependencies == null ? null : JSON.serialize(job.dependencies),
            RetryAttempts__c = job.retryAttempt,
            RetryHistory__c = job.retryHistory,
            RequeuedFrom__c = job.requeuedFromResultId
        );
        if (job.retryAttempt == 0) {
            Integer delayMinutes = delayMinutesOf(job);
            row.DelayMinutes__c = delayMinutes > 0 ? delayMinutes : null;
        }
        ChunkRun run = job instanceof ChunkJob ? ((ChunkJob) job).getRun() : null;
        if (run?.chunkSize != null) {
            row.ChunkRunId__c = run.runId;
            row.ChunkPage__c = run.currentPageNumber();
            row.ChunkPages__c = run.totalPages();
        }
        return row;
    }

    private AsyncResult__c buildResult(QueueableJob job) {
        AsyncResult__c result = identityOf(job);
        result.Id = resultIdByCustomJobId.get(job.customJobId);
        result.StartedAt__c = job.startedAt;
        result.FinishedAt__c = System.now();
        result.NextAttemptAt__c = null;
        if (payloadStorageOnAndJobDidNotSucceed(job)) {
            result.JobPayload__c = job.requeuePayload;
            result.PayloadSize__c = job.requeuePayloadSize;
            result.RequeueStatus__c = job.requeueStatus;
        }
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

    private void linkDependencyResults(
        List<QueueableJob> recordedJobs,
        Map<String, Async.Outcome> outcomeByCustomJobId
    ) {
        List<AsyncResult__c> toUpdate = new List<AsyncResult__c>();
        for (QueueableJob job : recordedJobs) {
            Async.Dependency decisive = decisiveDependency(job, outcomeByCustomJobId);
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
                    ActualOutcome__c = actual?.name() ?? 'NOT_RUN'
                )
            );
        }
        if (!toUpdate.isEmpty()) {
            update as system toUpdate;
        }
    }

    private static Async.Dependency decisiveDependency(
        QueueableJob job,
        Map<String, Async.Outcome> outcomeByCustomJobId
    ) {
        if (job.dependencies == null || job.dependencies.isEmpty()) {
            return null;
        }
        Async.Dependency blocking = QueueableManager.firstUnsatisfiedDependency(
            job,
            outcomeByCustomJobId
        );
        return blocking ?? job.dependencies[0];
    }
}
