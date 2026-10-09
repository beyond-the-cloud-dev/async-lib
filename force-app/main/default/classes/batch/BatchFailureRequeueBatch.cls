/**
 * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
 *
 * v3.0.0
 *
 * PMD False Positives:
 * - EmptyStatementBlock: Database.Batchable requires finish(), nothing to do after the last scope
 **/
@SuppressWarnings('PMD.EmptyStatementBlock')
public inherited sharing class BatchFailureRequeueBatch implements Database.Batchable<SObject>, Database.AllowsCallouts {
    private Database.Batchable<SObject> batch;
    private String batchJobId;
    private Async.BatchRecordLoader loader;

    public BatchFailureRequeueBatch(
        Database.Batchable<SObject> batch,
        Id batchJobId,
        Async.BatchRecordLoader loader
    ) {
        this.batch = batch;
        this.batchJobId = batchJobId;
        this.loader = loader;
    }

    public Database.QueryLocator start(Database.BatchableContext requeueContext) {
        return Database.getQueryLocator(
            [
                SELECT Id
                FROM AsyncResult__c
                WHERE
                    SalesforceJobId__c = :batchJobId
                    AND BatchPhase__c = :BatchFailureRecorder.PHASE_EXECUTE
                    AND BatchScopeTruncated__c = FALSE
                    AND RequeueStatus__c != :AsyncRequeue.STATUS_REQUEUED
                WITH SYSTEM_MODE
            ]
        );
    }

    // Marking here, not when the requeue is submitted, is what keeps a scope that throws again
    // open: the mark rolls back with the rest of the transaction.
    public void execute(Database.BatchableContext requeueContext, List<AsyncResult__c> scopes) {
        List<AsyncResult__c> stillOpen = lockScopesNotRequeuedMeanwhile(scopes);
        for (AsyncResult__c failedScope : stillOpen) {
            List<SObject> records = loader.load(recordIdsIn(failedScope.BatchScope__c));
            if (!records.isEmpty()) {
                batch.execute(requeueContext, records);
            }
            failedScope.RequeueStatus__c = AsyncRequeue.STATUS_REQUEUED;
        }
        update as system stillOpen;
    }

    public void finish(Database.BatchableContext requeueContext) {
    }

    private List<AsyncResult__c> lockScopesNotRequeuedMeanwhile(List<AsyncResult__c> scopes) {
        return [
            SELECT Id, BatchScope__c
            FROM AsyncResult__c
            WHERE Id IN :scopes AND RequeueStatus__c != :AsyncRequeue.STATUS_REQUEUED
            WITH SYSTEM_MODE
            FOR UPDATE
        ];
    }

    private Set<Id> recordIdsIn(String batchScope) {
        Set<Id> recordIds = new Set<Id>();
        for (String recordId : batchScope.split(',')) {
            recordIds.add((Id) recordId.trim());
        }
        return recordIds;
    }
}
