@IsTest
private class AsyncTest {
    private static final String ACCOUNT_NAME = 'Test Account';
    private static final String CUSTOM_ERROR_MESSAGE = 'Something goes wrong.';
    private static final String DUPLICATE_SIGNATURE_ERROR_MESSAGE = 'Attempt to enqueue job with duplicate queueable signature';
    private static final String TEST_SIGNATURE_NAME = 'SignatureName';

    @IsTest
    private static void shouldSchedule60QueueablesSuccessfully() {
        SuccessfulQueueableTest q = new SuccessfulQueueableTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Account]);
        Id initialQueuableChainBatchJobId;

        Test.startTest();
        for (Integer idx = 0; idx < 60; idx++) {
            Async.AsyncResult ar = Async.of(q).enqueue();
            if (Limits.getQueueableJobs() <= Limits.getLimitQueueableJobs()) {
                Assert.isFalse(ar.isEnqueuedViaBatch, 'Should not be enqueued via batch.');
            } else {
                Assert.isTrue(ar.isEnqueuedViaBatch, 'Should be enqueued via batch.');
            }
        }
        initialQueuableChainBatchJobId = Async.getQueueableChainBatchId();
        Test.stopTest();

        Assert.areEqual(51, [SELECT COUNT() FROM Account], 'Should have 51 job runs (50 queueable and 1 batch).');
        Assert.areEqual(
            1,
            [SELECT Id FROM AsyncApexJob WHERE ApexClass.Name = 'QueueableChainBatch' AND Status = 'Completed' AND Id = :initialQueuableChainBatchJobId].size(),
            'Should run only one batchable job with the rest, that should be successfully completed and with Id provided from framework.'
        );
    }

    @IsTest
    private static void shouldSchedule60QueueablesWitDelaySuccessfully() {
        SuccessfulQueueableTest q = new SuccessfulQueueableTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Account]);

        Test.startTest();
        for (Integer idx = 0; idx < 60; idx++) {
            Async.of(q)
                .delay(1)
                .enqueue();
        }
        Test.stopTest();

        Assert.areEqual(51, [SELECT COUNT() FROM Account], 'Should have 51 job runs (50 queueable and 1 batch).');
        Assert.areEqual(
            1,
            [SELECT Id FROM AsyncApexJob WHERE ApexClass.Name = 'QueueableChainBatch' AND Status = 'Completed'].size(),
            'Should run only one batchable job with the rest.'
        );
    }

    @IsTest
    private static void shouldSchedule60QueueablesSuccessfullyWithAllItemsFailedWithRollback() {
        FailureQueueableTest q = new FailureQueueableTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Account]);

        Test.startTest();
        for (Integer idx = 0; idx < 60; idx++) {
            Async.of(q)
                .enqueue();
        }
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Account], 'Should have no Accounts created.');
        Assert.areEqual(
            1,
            [SELECT Id FROM AsyncApexJob WHERE ApexClass.Name = 'QueueableChainBatch' AND Status = 'Completed'].size(),
            'Should run only one batchable job with the rest.'
        );
    }

    @IsTest
    private static void shouldSchedule60QueueablesSuccessfullyWithAllItemsFailedWithoutRollback() {
        FailureQueueableTest q = new FailureQueueableTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Account]);

        Test.startTest();
        for (Integer idx = 0; idx < 60; idx++) {
            Async.of(q)
                .doNotRollbackDatabaseOnFail()
                .enqueue();
        }
        Test.stopTest();

        Assert.areEqual(51, [SELECT COUNT() FROM Account], 'Inserted Accounts are not rollbacked.');
        Assert.areEqual(
            1,
            [SELECT Id FROM AsyncApexJob WHERE ApexClass.Name = 'QueueableChainBatch' AND Status = 'Completed'].size(),
            'Should run only one batchable job with the rest.'
        );
    }

    @IsTest
    private static void shouldOnlyScheduleOneJobDueToAsyncOptions() {
        SuccessfulQueueableTest q = new SuccessfulQueueableTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Account]);
        AsyncOptions options = new AsyncOptions();
        options.DuplicateSignature = QueueableDuplicateSignature.Builder().addString(TEST_SIGNATURE_NAME).build();

        Test.startTest();
        for (Integer idx = 0; idx < 50; idx++) {
            Async.of(q)
                .asyncOptions(options)
                .enqueue();
        }
        Test.stopTest();

        Assert.areEqual(1, [SELECT COUNT() FROM Account], 'Only one job should run.');
    }

    @IsTest
    private static void shouldFailChainOnDuplicateAsyncOptionsSignature() {
        SuccessfulQueueableTest q = new SuccessfulQueueableTest();

        AsyncOptions options = new AsyncOptions();
        options.DuplicateSignature = QueueableDuplicateSignature.Builder().addString(TEST_SIGNATURE_NAME).build();

        Test.startTest();
        try {
            Async.of(q)
                .asyncOptions(options)
                .failChainOnJobEnqueueFail()
                .enqueue();
            Async.of(q)
                .asyncOptions(options)
                .failChainOnJobEnqueueFail()
                .enqueue();
            Assert.fail('Should throw duplicate signature exception.');
        } catch (Exception ex) {
            Assert.areEqual(DUPLICATE_SIGNATURE_ERROR_MESSAGE, ex.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    private static void shouldFailChainDueToExecuteFailure() {
        FailureQueueableTest failureJob = new FailureQueueableTest();

        try {
            Test.startTest();
            Async.of(failureJob)
                .failChainOnJobExecuteFail()
                .enqueue();
            Test.stopTest();
            Assert.fail('Should throw duplicate signature exception.');
        } catch (Exception ex) {
            Assert.areEqual(CUSTOM_ERROR_MESSAGE, ex.getMessage());
        }
    }

    private class SuccessfulQueueableTest extends QueueableJob {
        public override void work(QueueableContext ctx) {
            insert new Account(Name = Async.getQueueableJobContext()?.currentJob?.uniqueName);
        }
    }

    private class FailureQueueableTest extends QueueableJob.WithCallouts {
        public override void work(QueueableContext ctx) {
            insert new Account(Name = Async.getQueueableJobContext()?.currentJob?.uniqueName);
            throw new CustomException(AsyncTest.CUSTOM_ERROR_MESSAGE);
        }
    }

    private class CustomException extends Exception {
    }
}
