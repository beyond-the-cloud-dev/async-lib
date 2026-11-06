/**
 * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
 *
 * v3.1.0
 *
 * PMD False Positives:
 * - ExcessivePublicCount / TooManyFields: the DTOs mirror the result row field by field
 **/
@SuppressWarnings('PMD.ExcessivePublicCount,PMD.TooManyFields')
public with sharing class AsyncJobTimelineController {
    public static final String ERROR_MESSAGE_NO_ACCESS = 'You cannot read async job results. Ask an admin for the Async Result Access permission set.';
    private static final String REQUEUE_PERMISSION = 'AsyncRequeue';

    @AuraEnabled
    public static TimelinePage load(AsyncJobTimelineRequest request) {
        try {
            TimelinePage page = AsyncJobTimelineLoader.pageFor(request);
            page.canRequeue = FeatureManagement.checkPermission(REQUEUE_PERMISSION);
            return page;
        } catch (QueryException queryFailure) {
            throw readableError(queryFailure);
        }
    }

    @AuraEnabled
    public static PollResult poll(Id recordId, List<String> chainIds) {
        try {
            PollResult result = new PollResult();
            result.fingerprint = AsyncJobTimelineLoader.fingerprintOf(recordId, chainIds);
            result.apexJobStatusById = AsyncJobTimelineLoader.apexJobStatusesFor(
                AsyncJobTimelineLoader.enqueuedJobIdsIn(chainIds)
            );
            return result;
        } catch (QueryException queryFailure) {
            throw readableError(queryFailure);
        }
    }

    @AuraEnabled
    public static RequeueOutcome requeue(List<Id> resultIds) {
        if (!FeatureManagement.checkPermission(REQUEUE_PERMISSION)) {
            throw auraError(QueueableManager.ERROR_MESSAGE_REQUEUE_PERMISSION);
        }
        Async.RequeueSummary summary;
        try {
            summary = Async.requeue(new Set<Id>(resultIds));
        } catch (Exception requeueFailure) {
            throw auraError(requeueFailure.getMessage());
        }
        RequeueOutcome outcome = new RequeueOutcome();
        outcome.requeued = summary.requeued;
        outcome.skipReasonByResultId = summary.skipReasonByResultId;
        outcome.droppedDependencyByResultId = summary.droppedDependencyByResultId;
        List<QueueableJob> replayed = summary.enqueueResult?.queueableChainState?.jobs;
        outcome.chainId = replayed == null || replayed.isEmpty() ? null : replayed[0].chainId;
        return outcome;
    }

    // getMessage() on an AuraHandledException returns "Script-thrown exception" unless the
    // message is also set explicitly.
    private static AuraHandledException auraError(String message) {
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }

    // A viewer without field access on a parent or child relationship gets "Variable does not
    // exist: tmpVarN" from a user-mode query, not an "Insufficient permissions" message.
    private static AuraHandledException readableError(QueryException queryFailure) {
        String message = queryFailure.getMessage();
        Boolean accessProblem =
            message.contains('Insufficient permissions') ||
            message.contains('is not supported') ||
            message.contains('No such column') ||
            message.contains('tmpVar');
        return auraError(accessProblem ? ERROR_MESSAGE_NO_ACCESS : message);
    }

    public class TimelinePage {
        @AuraEnabled
        public List<Sequence> sequences = new List<Sequence>();
        @AuraEnabled
        public Boolean hasMore = false;
        @AuraEnabled
        public Integer olderChainCount = 0;
        @AuraEnabled
        public Integer totalChainCount = 0;
        @AuraEnabled
        public Map<String, Integer> counts = new Map<String, Integer>();
        @AuraEnabled
        public Boolean canRequeue = false;
        @AuraEnabled
        public String fingerprint;
        @AuraEnabled
        public Datetime loadedAt;
    }

    public class Sequence {
        @AuraEnabled
        public String chainId;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public Datetime startedAt;
        @AuraEnabled
        public List<Step> steps = new List<Step>();

        public Sequence(String chainId) {
            this.chainId = chainId;
        }
    }

    public class Step {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String customJobId;
        @AuraEnabled
        public String className;
        @AuraEnabled
        public String jobName;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public String apexJobStatus;
        @AuraEnabled
        public String salesforceJobId;
        @AuraEnabled
        public Datetime createdAt;
        @AuraEnabled
        public Datetime startedAt;
        @AuraEnabled
        public Datetime finishedAt;
        @AuraEnabled
        public Datetime nextAttemptAt;
        @AuraEnabled
        public Integer chainSequence;
        @AuraEnabled
        public Integer priority;
        @AuraEnabled
        public Integer retryAttempts;
        @AuraEnabled
        public Integer chunkPage;
        @AuraEnabled
        public Integer chunkPages;
        @AuraEnabled
        public Integer delayMinutes;
        @AuraEnabled
        public String parentCustomJobId;
        @AuraEnabled
        public String addedByCustomJobId;
        @AuraEnabled
        public String chunkRunId;
        @AuraEnabled
        public String exceptionType;
        @AuraEnabled
        public String exceptionMessage;
        @AuraEnabled
        public String retryHistory;
        @AuraEnabled
        public String skipReason;
        @AuraEnabled
        public String requeueStatus;
        @AuraEnabled
        public Id requeuedFrom;
        @AuraEnabled
        public String requeuedFromName;
        @AuraEnabled
        public Id replayResultId;
        @AuraEnabled
        public String replayChainId;
        @AuraEnabled
        public Id dependsOnResult;
        @AuraEnabled
        public String dependencies;
        @AuraEnabled
        public List<LinkedRecord> records = new List<LinkedRecord>();

        public Step(
            AsyncResult__c row,
            Map<String, String> apexJobStatusById,
            Map<Id, String> nameById
        ) {
            id = row.Id;
            name = row.Name;
            customJobId = row.CustomJobId__c;
            className = row.ClassName__c;
            jobName = row.JobName__c;
            status = row.Status__c;
            salesforceJobId = row.SalesforceJobId__c;
            apexJobStatus = apexJobStatusById.get(row.SalesforceJobId__c);
            createdAt = row.CreatedDate;
            startedAt = row.StartedAt__c;
            finishedAt = row.FinishedAt__c;
            nextAttemptAt = row.NextAttemptAt__c;
            chainSequence = row.ChainSequence__c?.intValue();
            priority = row.Priority__c?.intValue();
            retryAttempts = row.RetryAttempts__c?.intValue();
            chunkPage = row.ChunkPage__c?.intValue();
            chunkPages = row.ChunkPages__c?.intValue();
            delayMinutes = row.DelayMinutes__c?.intValue();
            parentCustomJobId = row.ParentCustomJobId__c;
            addedByCustomJobId = row.AddedByCustomJobId__c;
            chunkRunId = row.ChunkRunId__c;
            exceptionType = row.ExceptionType__c;
            exceptionMessage = row.ExceptionMessage__c;
            retryHistory = row.RetryHistory__c;
            skipReason = row.SkipReason__c;
            requeueStatus = row.RequeueStatus__c;
            requeuedFrom = row.RequeuedFrom__c;
            requeuedFromName = row.RequeuedFrom__r?.Name;
            dependsOnResult = row.DependsOnResult__c;
            dependencies = row.Dependencies__c;
            for (AsyncResultLink__c link : row.Links__r) {
                records.add(new LinkedRecord(link, nameById));
            }
        }
    }

    public class LinkedRecord {
        @AuraEnabled
        public String key;
        @AuraEnabled
        public String source;
        @AuraEnabled
        public String objectName;
        @AuraEnabled
        public String name;

        public LinkedRecord(AsyncResultLink__c link, Map<Id, String> nameById) {
            key = link.Key__c;
            source = link.Source__c;
            objectName = link.ObjectName__c;
            name = nameById.get(AsyncJobTimelineLoader.salesforceIdOf(link)) ?? link.Key__c;
        }
    }

    public class PollResult {
        @AuraEnabled
        public String fingerprint;
        @AuraEnabled
        public Map<String, String> apexJobStatusById = new Map<String, String>();
    }

    public class RequeueOutcome {
        @AuraEnabled
        public List<Id> requeued = new List<Id>();
        @AuraEnabled
        public Map<Id, String> skipReasonByResultId = new Map<Id, String>();
        @AuraEnabled
        public Map<Id, String> droppedDependencyByResultId = new Map<Id, String>();
        @AuraEnabled
        public String chainId;
    }
}
