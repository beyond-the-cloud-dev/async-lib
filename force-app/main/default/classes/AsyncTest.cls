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

        Test.startTest();
        for (Integer idx = 0; idx < 60; idx++) {
            Async.of(q).enqueue();
        }
        Test.stopTest();

        Assert.areEqual(50, [SELECT COUNT() FROM Account], 'Should have 50 normal job runs.');
        // String queuableChainSchedulerLike = QueueableChainScheduler.QUEUEABLE_CHAIN_SCHEDULER_NAME + '%';
        // Assert.isFalse(
        //     [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name LIKE :queuableChainSchedulerLike].isEmpty(),
        //     'Should run scheduled job with the rest.'
        // );
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

        Assert.areEqual(50, [SELECT COUNT() FROM Account], 'Should have 50 normal job runs.');
        // String queuableChainSchedulerLike = QueueableChainScheduler.QUEUEABLE_CHAIN_SCHEDULER_NAME + '%';
        // Assert.isFalse(
        //     [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name LIKE :queuableChainSchedulerLike].isEmpty(),
        //     'Should run scheduled job with the rest.'
        // );
    }

    @IsTest
    private static void shouldSchedule60QueueablesSuccessfullyWithAllItemsFailed() {
        FailureQueueableTest q = new FailureQueueableTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Account]);

        Test.startTest();
        for (Integer idx = 0; idx < 60; idx++) {
            Async.of(q).enqueue();
        }
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Account], 'Should have no Accounts created.');
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

    private class SuccessfulQueueableTest implements Queueable {
        public void execute(QueueableContext context) {
            insert new Account(Name = 'Success Account');
        }
    }

    private class FailureQueueableTest implements Queueable {
        public void execute(QueueableContext context) {
            insert new Account(Name = 'Failure Account');
            throw new CustomException(AsyncTest.CUSTOM_ERROR_MESSAGE);
        }
    }

    private class CustomException extends Exception {
    }
}
