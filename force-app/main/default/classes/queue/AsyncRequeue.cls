public inherited sharing class AsyncRequeue {
    public static final String STATUS_STORED = 'Stored';
    public static final String STATUS_TOO_LARGE = 'TooLarge';
    public static final String STATUS_NOT_SERIALIZABLE = 'NotSerializable';
    public static final String STATUS_REQUEUED = 'Requeued';

    public static final Integer MAX_CHARS_PER_REQUEUE = 2000000;

    private static final String STORE_PAYLOAD_YES = 'Yes';

    public static void captureJobAsHandedOver(QueueableJob job) {
        if (!storesPayload(job)) {
            return;
        }
        if (job instanceof ChunkJob || job.isFinalizer) {
            job.requeueStatus = STATUS_NOT_SERIALIZABLE;
            return;
        }

        String payload;
        try {
            payload = JobPayload.forJob(job);
        } catch (Exception captureFailure) {
            recordNotSerializable(job, captureFailure.getMessage());
            return;
        }
        if (payload == null) {
            recordNotSerializable(job, QueueableManager.CAUSE_SERIALIZER_RETURNED_NULL);
            return;
        }

        job.requeuePayloadSize = payload.length();
        if (payload.length() > JobPayload.MAX_CHARS) {
            job.requeueStatus = STATUS_TOO_LARGE;
            return;
        }
        job.requeueStatus = STATUS_STORED;
        job.requeuePayload = payload;
    }

    public static Boolean storesPayload(QueueableJob job) {
        return QueueableManager.settingFor(
                job.className,
                QueueableJobSetting__mdt.StoreJobPayload__c
            ) == STORE_PAYLOAD_YES;
    }

    public static Async.RequeueSummary run(Set<Id> resultIds) {
        Async.RequeueSummary summary = new Async.RequeueSummary();
        if (resultIds == null || resultIds.isEmpty()) {
            return summary;
        }
        List<AsyncResult__c> replayable = replayableOrExplained(resultIds, summary);
        assertPayloadsWillFitInHeap(replayable);

        QueueableBuilder replay = chainRebuilt(lockRowsAndReadPayloads(replayable), summary);
        if (summary.requeued.isEmpty()) {
            return summary;
        }
        summary.enqueueResult = replay.enqueue();
        markRequeued(summary.requeued);
        return summary;
    }

    private static List<AsyncResult__c> replayableOrExplained(
        Set<Id> resultIds,
        Async.RequeueSummary summary
    ) {
        List<AsyncResult__c> replayable = new List<AsyncResult__c>();
        for (AsyncResult__c row : readWithoutPayloads(resultIds)) {
            String blocker = reasonItCannotBeRequeued(row);
            if (blocker == null) {
                replayable.add(row);
            } else {
                summary.skipReasonByResultId.put(row.Id, blocker);
            }
        }
        for (Id missingId : missingIds(resultIds, summary, replayable)) {
            summary.skipReasonByResultId.put(missingId, QueueableManager.REQUEUE_SKIPPED_NO_RECORD);
        }
        return replayable;
    }

    private static QueueableBuilder chainRebuilt(
        List<AsyncResult__c> lockedRows,
        Async.RequeueSummary summary
    ) {
        QueueableBuilder replay = Async.queueable();
        for (AsyncResult__c row : lockedRows) {
            if (wasRequeuedWhileWaitingForTheLock(row)) {
                summary.skipReasonByResultId.put(
                    row.Id,
                    QueueableManager.REQUEUE_SKIPPED_ALREADY_REQUEUED
                );
                continue;
            }
            QueueableJob job = rebuildOrExplain(row, summary);
            if (job == null) {
                continue;
            }
            job.requeuedFromResultId = row.Id;
            replay.chain(job);
            summary.requeued.add(row.Id);
        }
        return replay;
    }

    private static void recordNotSerializable(QueueableJob job, String cause) {
        job.requeueStatus = STATUS_NOT_SERIALIZABLE;
        job.recordConfigurationWarning(
            String.format(
                QueueableManager.WARNING_PAYLOAD_NOT_CAPTURED,
                new List<String>{ job.className, cause }
            )
        );
    }

    private static List<AsyncResult__c> readWithoutPayloads(Set<Id> resultIds) {
        return [
            SELECT Id, ClassName__c, PayloadSize__c, RequeueStatus__c
            FROM AsyncResult__c
            WHERE Id IN :resultIds
            WITH SYSTEM_MODE
        ];
    }

    private static List<AsyncResult__c> lockRowsAndReadPayloads(List<AsyncResult__c> rows) {
        return [
            SELECT Id, ClassName__c, JobPayload__c, RequeueStatus__c
            FROM AsyncResult__c
            WHERE Id IN :rows
            WITH SYSTEM_MODE
            FOR UPDATE
        ];
    }

    private static Set<Id> missingIds(
        Set<Id> requestedIds,
        Async.RequeueSummary summary,
        List<AsyncResult__c> replayable
    ) {
        Set<Id> missing = new Set<Id>(requestedIds);
        missing.removeAll(summary.skipReasonByResultId.keySet());
        missing.removeAll(new Map<Id, AsyncResult__c>(replayable).keySet());
        return missing;
    }

    private static String reasonItCannotBeRequeued(AsyncResult__c row) {
        if (row.RequeueStatus__c == STATUS_STORED) {
            return null;
        }
        if (row.RequeueStatus__c == STATUS_REQUEUED) {
            return QueueableManager.REQUEUE_SKIPPED_ALREADY_REQUEUED;
        }
        if (String.isBlank(row.RequeueStatus__c)) {
            return QueueableManager.REQUEUE_SKIPPED_NO_PAYLOAD;
        }
        return String.format(
            QueueableManager.REQUEUE_SKIPPED_BY_STATUS,
            new List<String>{ row.RequeueStatus__c }
        );
    }

    private static void assertPayloadsWillFitInHeap(List<AsyncResult__c> rows) {
        Integer totalChars = 0;
        for (AsyncResult__c row : rows) {
            totalChars += (row.PayloadSize__c ?? 0).intValue();
        }
        if (totalChars > MAX_CHARS_PER_REQUEUE) {
            throw new Async.IllegalArgumentException(
                String.format(
                    QueueableManager.ERROR_MESSAGE_REQUEUE_BUDGET_EXCEEDED,
                    new List<String>{
                        String.valueOf(totalChars),
                        String.valueOf(MAX_CHARS_PER_REQUEUE),
                        String.valueOf(rows.size())
                    }
                )
            );
        }
    }

    private static Boolean wasRequeuedWhileWaitingForTheLock(AsyncResult__c lockedRow) {
        return lockedRow.RequeueStatus__c != STATUS_STORED;
    }

    private static QueueableJob rebuildOrExplain(AsyncResult__c row, Async.RequeueSummary summary) {
        try {
            QueueableJob job = JobPayload.toJob(row.ClassName__c, row.JobPayload__c);
            if (job == null) {
                summary.skipReasonByResultId.put(
                    row.Id,
                    String.format(
                        QueueableManager.REQUEUE_SKIPPED_CLASS_NOT_FOUND,
                        new List<String>{ row.ClassName__c, QueueableManager.API_PREFIX }
                    )
                );
                return null;
            }
            QueueableManager.assertStateHandlingDeclared(job);
            return job;
        } catch (Exception rebuildFailure) {
            summary.skipReasonByResultId.put(row.Id, rebuildFailure.getMessage());
            return null;
        }
    }

    private static void markRequeued(List<Id> resultIds) {
        List<AsyncResult__c> toMark = new List<AsyncResult__c>();
        for (Id resultId : resultIds) {
            toMark.add(new AsyncResult__c(Id = resultId, RequeueStatus__c = STATUS_REQUEUED));
        }
        update as system toMark;
    }
}
