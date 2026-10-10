/**
 * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
 *
 * v3.0.0
 **/
@IsTest
public class NsTestBatchFailure {
    private static final Id FAILED_JOB_ID = fakeBatchJobId();

    @IsTest
    static void shouldRecordAndLogASubscriberBatchFailure() {
        btcdev.AsyncMock.jobSettings(
            new List<btcdev__QueueableJobSetting__mdt>{
                new btcdev__QueueableJobSetting__mdt(
                    btcdev__QueueableJobName__c = 'All',
                    btcdev__CreateResult__c = true,
                    btcdev__LoggerClass__c = 'NsBatchFailureLogger'
                )
            }
        );
        List<Account> accounts = batchAccounts(2);
        NsFailingBatch.fails = true;

        Id batchJobId;
        try {
            Test.startTest();
            batchJobId = btcdev.Async.batchable(new NsFailingBatch()).execute().salesforceJobId;
            Test.stopTest();
        } catch (NsFailingBatch.NsBatchException rethrownByStopTest) {
            System.assertEquals('ns batch failure', rethrownByStopTest.getMessage());
        }
        Test.getEventBus().deliver();

        btcdev__AsyncResult__c failure = [
            SELECT
                btcdev__ClassName__c,
                btcdev__SalesforceJobId__c,
                btcdev__BatchPhase__c,
                btcdev__BatchScope__c,
                btcdev__ExceptionMessage__c
            FROM btcdev__AsyncResult__c
        ];
        System.assertEquals(NsFailingBatch.class.getName(), failure.btcdev__ClassName__c);
        System.assertEquals((String) batchJobId, failure.btcdev__SalesforceJobId__c);
        System.assertEquals('EXECUTE', failure.btcdev__BatchPhase__c);
        System.assertEquals('ns batch failure', failure.btcdev__ExceptionMessage__c);
        System.assert(failure.btcdev__BatchScope__c.contains(accounts[0].Id));

        Account logged = [SELECT Site, Description FROM Account WHERE Name = 'NS-BATCH-LOGGED'];
        System.assertEquals(
            'BATCHABLE|EXECUTE|false',
            logged.Site,
            'The batch fields of FailureContext must be readable from a subscriber logger'
        );
        System.assert(logged.Description.startsWith(batchJobId + '|'), logged.Description);
    }

    @IsTest
    static void shouldRequeueASubscriberBatchWithAFieldList() {
        btcdev__AsyncResult__c failure = failedScope(batchAccounts(3));

        Test.startTest();
        btcdev.Async.RequeueSummary summary = btcdev.Async.requeueBatchFailures(
            new NsFailingBatch(),
            FAILED_JOB_ID,
            new List<SObjectField>{ Account.Name }
        );
        Test.stopTest();

        System.assertEquals(new List<Id>{ failure.Id }, summary.requeued);
        System.assertNotEquals(null, summary.enqueueResult.salesforceJobId);
        System.assertEquals(
            3,
            [SELECT COUNT() FROM Account WHERE Site LIKE 'ns-processed:NS-BATCH-%'],
            'Package code must be able to hold and call a subscriber batch'
        );
        System.assertEquals('Requeued', requeueStatusOf(failure));
    }

    @IsTest
    static void shouldRequeueASubscriberBatchWithParentFieldsAsStrings() {
        failedScope(batchAccounts(1));
        NsFailingBatch.readsOwner = true;

        Test.startTest();
        btcdev.Async.requeueBatchFailures(
            new NsFailingBatch(),
            FAILED_JOB_ID,
            new List<String>{ 'Name', 'Owner.Name' }
        );
        Test.stopTest();

        System.assertEquals(UserInfo.getName(), [SELECT Description FROM Account].Description);
    }

    @IsTest
    static void shouldRequeueASubscriberBatchThroughASubscriberLoader() {
        btcdev__AsyncResult__c failure = failedScope(batchAccounts(2));
        NsFailingBatch.readsOwner = true;

        Test.startTest();
        btcdev.Async.requeueBatchFailures(new NsFailingBatch(), FAILED_JOB_ID, new OwnerLoader());
        Test.stopTest();

        System.assertEquals(
            2,
            [SELECT COUNT() FROM Account WHERE Site LIKE 'ns-processed:NS-BATCH-%'],
            'A subscriber loader must survive serialization inside the package batch'
        );
        System.assertEquals('Requeued', requeueStatusOf(failure));
    }

    @IsTest
    static void shouldPointABatchFailureAtItsOwnRequeueCallWithTheNamespace() {
        btcdev__AsyncResult__c failure = failedScope(batchAccounts(1));

        btcdev.Async.RequeueSummary summary = btcdev.Async.requeue(failure.Id);

        System.assert(
            summary.skipReasonByResultId.get(failure.Id).contains('requeueBatchFailures'),
            summary.skipReasonByResultId.get(failure.Id)
        );
    }

    private static List<Account> batchAccounts(Integer howMany) {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < howMany; i++) {
            accounts.add(new Account(Name = 'NS-BATCH-' + i));
        }
        insert accounts;
        return accounts;
    }

    private static btcdev__AsyncResult__c failedScope(List<Account> accounts) {
        btcdev__AsyncResult__c failure = new btcdev__AsyncResult__c(
            btcdev__Status__c = 'FAILED',
            btcdev__ClassName__c = NsFailingBatch.class.getName(),
            btcdev__SalesforceJobId__c = FAILED_JOB_ID,
            btcdev__BatchPhase__c = 'EXECUTE',
            btcdev__BatchScope__c = String.join(
                new List<Id>(new Map<Id, Account>(accounts).keySet()),
                ','
            )
        );
        insert failure;
        return failure;
    }

    private static String requeueStatusOf(btcdev__AsyncResult__c failure) {
        return [
            SELECT btcdev__RequeueStatus__c
            FROM btcdev__AsyncResult__c
            WHERE Id = :failure.Id
        ]
        .btcdev__RequeueStatus__c;
    }

    private static Id fakeBatchJobId() {
        return AsyncApexJob.SObjectType.getDescribe().getKeyPrefix() + '0'.repeat(11) + '1AAA';
    }

    public class OwnerLoader implements btcdev.Async.BatchRecordLoader {
        public List<SObject> load(Set<Id> failedRecordIds) {
            return [SELECT Id, Name, Owner.Name FROM Account WHERE Id IN :failedRecordIds];
        }
    }
}
