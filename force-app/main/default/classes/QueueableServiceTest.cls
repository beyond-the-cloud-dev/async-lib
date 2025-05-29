@IsTest
private class QueueableServiceTest {
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
            QueueableService.enqueueJob(q);
        }
        Test.stopTest();

        Assert.areEqual(50, [SELECT COUNT() FROM Account], 'Should have 50 normal job runs.');
        String queuableChainSchedulerLike = QueueableChainScheduler.QUEUEABLE_CHAIN_SCHEDULER_NAME + '%';
        Assert.isFalse(
            [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name LIKE :queuableChainSchedulerLike].isEmpty(),
            'Should run scheduled job with the rest.'
        );
    }

    @IsTest
    private static void shouldSchedule60QueueablesWitDelaySuccessfully() {
        SuccessfulQueueableTest q = new SuccessfulQueueableTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Account]);

        Test.startTest();
        for (Integer idx = 0; idx < 60; idx++) {
            QueueableService.enqueueJob(q, 1);
        }
        Test.stopTest();

        Assert.areEqual(50, [SELECT COUNT() FROM Account], 'Should have 50 normal job runs.');
        String queuableChainSchedulerLike = QueueableChainScheduler.QUEUEABLE_CHAIN_SCHEDULER_NAME + '%';
        Assert.isFalse(
            [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name LIKE :queuableChainSchedulerLike].isEmpty(),
            'Should run scheduled job with the rest.'
        );
    }

    @IsTest
    private static void shouldSchedule60QueueablesSuccessfullyWithAllItemsFailed() {
        FailureQueueableTest q = new FailureQueueableTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Account]);

        Test.startTest();
        for (Integer idx = 0; idx < 60; idx++) {
            QueueableService.enqueueJob(q);
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
            QueueableService.enqueueJob(q, options);
        }
        Test.stopTest();

        Assert.areEqual(1, [SELECT COUNT() FROM Account], 'Only one job should run.');
    }

    private class SuccessfulQueueableTest extends QueueableChainItem {
        public override void work(QueueableContext context) {
            insert new Account(Name = this.name);
        }
    }

    private class FailureQueueableTest extends QueueableChainItem {
        public override void work(QueueableContext context) {
            insert new Account(Name = this.name);
            throw new CustomException(QueueableServiceTest.CUSTOM_ERROR_MESSAGE);
        }
    }

    private class CustomException extends Exception {
    }
}
