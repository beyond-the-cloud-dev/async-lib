/**
 * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
 *
 * v3.0.0
 **/
public inherited sharing class BatchFailureRequeue {
    private static final Integer ONE_FAILED_SCOPE_PER_TRANSACTION = 1;

    public static Async.RequeueSummary run(
        Object batch,
        Id batchJobId,
        Async.BatchRecordLoader loader
    ) {
        Database.Batchable<SObject> failedBatch = BatchRequeueGuard.asBatch(batch);
        BatchRequeueGuard.assertJobIdAndLoaderGiven(batchJobId, loader);
        BatchRequeueGuard.assertLoaderOutlivesThisTransaction(loader);

        Async.RequeueSummary summary = new Async.RequeueSummary();
        List<AsyncResult__c> failedScopes = requeueableOrExplained(batchJobId, summary);
        if (failedScopes.isEmpty()) {
            if (summary.skipReasonByResultId.isEmpty()) {
                BatchRequeueGuard.assertTheJobReallyHadNoFailures(batchJobId);
            }
            return summary;
        }
        BatchRequeueGuard.assertSameClass(failedBatch, failedScopes[0]);
        if (loader instanceof BatchFieldReload) {
            ((BatchFieldReload) loader).assertQueryIsValidFor(firstRecordIdOf(failedScopes[0]));
        }

        Id requeueJobId = Database.executeBatch(
            new BatchFailureRequeueBatch(failedBatch, batchJobId, loader),
            ONE_FAILED_SCOPE_PER_TRANSACTION
        );
        summary.enqueueResult = new Async.Result(requeueJobId)
            .setAsyncType(Async.AsyncType.BATCHABLE);
        summary.requeued.addAll(new List<Id>(new Map<Id, AsyncResult__c>(failedScopes).keySet()));
        return summary;
    }

    public static Async.BatchRecordLoader reloading(List<SObjectField> fields) {
        if (fields == null) {
            return null;
        }
        List<String> fieldPaths = new List<String>();
        for (SObjectField field : fields) {
            fieldPaths.add(field.getDescribe().getName());
        }
        return new BatchFieldReload(fieldPaths);
    }

    public static Async.BatchRecordLoader reloading(List<String> fieldPaths) {
        return fieldPaths == null ? null : new BatchFieldReload(fieldPaths);
    }

    private static List<AsyncResult__c> requeueableOrExplained(
        Id batchJobId,
        Async.RequeueSummary summary
    ) {
        String jobId = batchJobId;
        List<AsyncResult__c> requeueable = new List<AsyncResult__c>();
        for (AsyncResult__c failure : [
            SELECT Id, ClassName__c, BatchPhase__c, BatchScopeTruncated__c, RequeueStatus__c
            FROM AsyncResult__c
            WHERE SalesforceJobId__c = :jobId AND BatchPhase__c != NULL
            WITH SYSTEM_MODE
            ORDER BY CreatedDate
        ]) {
            String blocker = reasonItCannotBeRequeued(failure);
            if (blocker == null) {
                requeueable.add(failure);
            } else {
                summary.skipReasonByResultId.put(failure.Id, blocker);
            }
        }
        return requeueable;
    }

    private static String reasonItCannotBeRequeued(AsyncResult__c failure) {
        if (failure.RequeueStatus__c == AsyncRequeue.STATUS_REQUEUED) {
            return QueueableManager.REQUEUE_SKIPPED_ALREADY_REQUEUED;
        }
        if (failure.BatchPhase__c != BatchFailureRecorder.PHASE_EXECUTE) {
            return String.format(
                QueueableManager.REQUEUE_SKIPPED_BATCH_PHASE,
                new List<String>{ failure.BatchPhase__c }
            );
        }
        if (failure.BatchScopeTruncated__c) {
            return QueueableManager.REQUEUE_SKIPPED_BATCH_SCOPE_TRUNCATED;
        }
        return null;
    }

    private static Id firstRecordIdOf(AsyncResult__c failedScope) {
        String scope = [
            SELECT BatchScope__c
            FROM AsyncResult__c
            WHERE Id = :failedScope.Id
            WITH SYSTEM_MODE
        ]
        .BatchScope__c;
        return (Id) scope.substringBefore(',');
    }
}
