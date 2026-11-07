/**
 * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
 *
 * v3.2.0
 **/
public with sharing class AsyncJobTimelineLoader {
    private static final Integer DEFAULT_DAYS_BACK = 7;
    private static final Integer DEFAULT_CHAIN_LIMIT = 10;

    public static AsyncJobTimelineController.TimelinePage pageFor(AsyncJobTimelineRequest request) {
        Id recordId = request.recordId;
        Integer daysBack = request.daysBack ?? DEFAULT_DAYS_BACK;
        Integer chainLimit = request.chainLimit ?? DEFAULT_CHAIN_LIMIT;
        Integer chainOffset = request.chainOffset ?? 0;
        String statusFilter = request.statusFilter;
        AsyncJobTimelineChains chains = new AsyncJobTimelineChains(recordId, daysBack);
        List<String> chainIds = chains.idsMatching(statusFilter, request.keepChainIds);
        List<String> pageChainIds = AsyncJobTimelineChains.slice(chainIds, chainOffset, chainLimit);

        AsyncJobTimelineController.TimelinePage page = new AsyncJobTimelineController.TimelinePage();
        page.hasMore = chainIds.size() > chainOffset + chainLimit;
        page.totalChainCount = chainIds.size();
        page.fingerprint = fingerprintOf(recordId, pageChainIds);
        List<AsyncResult__c> rows = rowsOf(pageChainIds);
        chains.refreshFrom(rows);
        page.counts = chains.counts();
        page.olderChainCount = chains.olderCount();
        page.sequences = sequencesOf(pageChainIds, rows);
        page.loadedAt = System.now();
        return page;
    }

    private static List<AsyncJobTimelineController.Sequence> sequencesOf(
        List<String> chainIds,
        List<AsyncResult__c> rows
    ) {
        Map<String, AsyncJobTimelineController.Sequence> byChain = new Map<String, AsyncJobTimelineController.Sequence>();
        for (String chainId : chainIds) {
            byChain.put(chainId, new AsyncJobTimelineController.Sequence(chainId));
        }
        if (chainIds.isEmpty()) {
            return byChain.values();
        }
        Map<String, String> apexJobStatusById = apexJobStatusesFor(enqueuedJobIdsOf(rows));
        Map<Id, String> nameById = AsyncJobTimelineNames.of(linkedRecordIdsOf(rows));
        Map<Id, AsyncResult__c> replayBySourceId = replaysOf(rows);
        for (AsyncResult__c row : rows) {
            AsyncJobTimelineController.Sequence sequence = byChain.get(row.ChainId__c);
            AsyncJobTimelineController.Step step = new AsyncJobTimelineController.Step(
                row,
                apexJobStatusById,
                nameById
            );
            AsyncResult__c replay = replayBySourceId.get(row.Id);
            step.replayResultId = replay?.Id;
            step.replayChainId = replay?.ChainId__c;
            sequence.steps.add(step);
            sequence.name = sequence.name ?? row.ChainName__c;
            sequence.startedAt = earlier(sequence.startedAt, row.CreatedDate);
        }
        List<AsyncJobTimelineController.Sequence> ordered = new List<AsyncJobTimelineController.Sequence>();
        for (String chainId : chainIds) {
            AsyncJobTimelineController.Sequence sequence = byChain.get(chainId);
            sequence.name = sequence.name ?? firstStepNameOf(sequence);
            ordered.add(sequence);
        }
        return ordered;
    }

    private static List<AsyncResult__c> rowsOf(List<String> chainIds) {
        return [
            SELECT
                Id,
                Name,
                CustomJobId__c,
                ChainId__c,
                ChainName__c,
                ChainSequence__c,
                ClassName__c,
                JobName__c,
                Status__c,
                SalesforceJobId__c,
                CreatedDate,
                StartedAt__c,
                FinishedAt__c,
                NextAttemptAt__c,
                Priority__c,
                RetryAttempts__c,
                RetryHistory__c,
                ChunkRunId__c,
                ChunkPage__c,
                ChunkPages__c,
                DelayMinutes__c,
                ParentCustomJobId__c,
                AddedByCustomJobId__c,
                ExceptionType__c,
                ExceptionMessage__c,
                SkipReason__c,
                RequeueStatus__c,
                RequeuedFrom__c,
                RequeuedFrom__r.Name,
                DependsOnResult__c,
                Dependencies__c,
                (SELECT Key__c, Source__c, ObjectName__c FROM Links__r ORDER BY CreatedDate, Id)
            FROM AsyncResult__c
            WHERE ChainId__c IN :chainIds
            WITH USER_MODE
            ORDER BY ChainSequence__c NULLS LAST, CreatedDate
        ];
    }

    private static Map<Id, AsyncResult__c> replaysOf(List<AsyncResult__c> rows) {
        Set<Id> requeuedIds = new Set<Id>();
        for (AsyncResult__c row : rows) {
            if (row.RequeueStatus__c == AsyncRequeue.STATUS_REQUEUED) {
                requeuedIds.add(row.Id);
            }
        }
        Map<Id, AsyncResult__c> replayBySourceId = new Map<Id, AsyncResult__c>();
        if (requeuedIds.isEmpty()) {
            return replayBySourceId;
        }
        for (AsyncResult__c replay : [
            SELECT Id, ChainId__c, RequeuedFrom__c
            FROM AsyncResult__c
            WHERE RequeuedFrom__c IN :requeuedIds
            WITH USER_MODE
            ORDER BY CreatedDate DESC
        ]) {
            if (!replayBySourceId.containsKey(replay.RequeuedFrom__c)) {
                replayBySourceId.put(replay.RequeuedFrom__c, replay);
            }
        }
        return replayBySourceId;
    }

    private static Set<Id> enqueuedJobIdsOf(List<AsyncResult__c> rows) {
        Set<Id> jobIds = new Set<Id>();
        for (AsyncResult__c row : rows) {
            if (
                row.Status__c == QueueableManager.STATUS_ENQUEUED &&
                row.SalesforceJobId__c != null
            ) {
                jobIds.add(row.SalesforceJobId__c);
            }
        }
        return jobIds;
    }

    public static Set<Id> enqueuedJobIdsIn(List<String> chainIds) {
        Set<Id> jobIds = new Set<Id>();
        for (AsyncResult__c row : [
            SELECT SalesforceJobId__c
            FROM AsyncResult__c
            WHERE
                ChainId__c IN :chainIds
                AND Status__c = :QueueableManager.STATUS_ENQUEUED
                AND SalesforceJobId__c != NULL
            WITH USER_MODE
        ]) {
            jobIds.add(row.SalesforceJobId__c);
        }
        return jobIds;
    }

    public static Map<String, String> apexJobStatusesFor(Set<Id> jobIds) {
        Map<String, String> statusById = new Map<String, String>();
        if (jobIds.isEmpty()) {
            return statusById;
        }
        for (AsyncApexJob job : [
            SELECT Id, Status
            FROM AsyncApexJob
            WHERE Id IN :jobIds
            WITH USER_MODE
        ]) {
            statusById.put(job.Id, job.Status);
        }
        return statusById;
    }

    private static Set<Id> linkedRecordIdsOf(List<AsyncResult__c> rows) {
        Set<Id> recordIds = new Set<Id>();
        for (AsyncResult__c row : rows) {
            for (AsyncResultLink__c link : row.Links__r) {
                Id recordId = salesforceIdOf(link);
                if (recordId != null) {
                    recordIds.add(recordId);
                }
            }
        }
        return recordIds;
    }

    public static Id salesforceIdOf(AsyncResultLink__c link) {
        Boolean salesforceId =
            link.Source__c == QueueableManager.SOURCE_SALESFORCE && link.Key__c instanceof Id;
        return salesforceId ? (Id) link.Key__c : null;
    }

    public static String fingerprintOf(Id recordId, List<String> chainIds) {
        List<String> parts = new List<String>();
        for (AggregateResult statusCount : [
            SELECT Status__c status, COUNT(Id) total, MAX(LastModifiedDate) touched
            FROM AsyncResult__c
            WHERE ChainId__c IN :chainIds
            WITH USER_MODE
            GROUP BY Status__c
            ORDER BY Status__c
        ]) {
            Datetime touched = (Datetime) statusCount.get('touched');
            parts.add(
                statusCount.get('status') +
                    ':' +
                    statusCount.get('total') +
                    ':' +
                    (touched == null ? '' : String.valueOf(touched.getTime()))
            );
        }
        Integer links = [
            SELECT COUNT()
            FROM AsyncResultLink__c
            WHERE Key__c = :recordId AND Source__c = :QueueableManager.SOURCE_SALESFORCE
            WITH USER_MODE
        ];
        parts.add('links:' + links);
        return String.join(parts, '|');
    }

    private static Datetime earlier(Datetime first, Datetime second) {
        return first == null || second < first ? second : first;
    }

    private static String firstStepNameOf(AsyncJobTimelineController.Sequence sequence) {
        AsyncJobTimelineController.Step first = sequence.steps[0];
        return first.jobName ?? first.className;
    }
}
