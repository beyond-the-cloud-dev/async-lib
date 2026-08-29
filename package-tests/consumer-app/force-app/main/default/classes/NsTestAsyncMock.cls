@IsTest
public class NsTestAsyncMock {
    @IsTest
    static void shouldExposeMockSetupAndContextApi() {
        btcdev.AsyncMock.QueueableMockSetup qs = btcdev.AsyncMock.whenQueueable('testMock');
        System.assertNotEquals(null, qs);

        btcdev.AsyncMock.FinalizerMockSetup fs = btcdev.AsyncMock.whenFinalizer('testFinalizer');
        System.assertNotEquals(null, fs);

        System.assertEquals(true, btcdev.AsyncMock.hasQueueableMock('testMock'));
        System.assertEquals(true, btcdev.AsyncMock.hasFinalizerMock('testFinalizer'));
        System.assertEquals(false, btcdev.AsyncMock.hasQueueableMock('nonexistent'));
        System.assertEquals(false, btcdev.AsyncMock.hasFinalizerMock('nonexistent'));

        btcdev.AsyncMock.QueueableMockSetup defaultQs = btcdev.AsyncMock.whenQueueableDefault();
        System.assertNotEquals(null, defaultQs);

        btcdev.AsyncMock.FinalizerMockSetup defaultFs = btcdev.AsyncMock.whenFinalizerDefault();
        System.assertNotEquals(null, defaultFs);

        btcdev.AsyncMock.MockQueueableContext mqc = new btcdev.AsyncMock.MockQueueableContext();
        System.assertNotEquals(null, mqc);

        btcdev.AsyncMock.MockFinalizerContext mfc = new btcdev.AsyncMock.MockFinalizerContext();
        System.assertNotEquals(null, mfc);

        btcdev.AsyncMock.reset();
        System.assertEquals(false, btcdev.AsyncMock.hasQueueableMock('testMock'));
        System.assertEquals(false, btcdev.AsyncMock.hasFinalizerMock('testFinalizer'));
    }

    public class NsMockException extends Exception {
    }

    public class NeverFailingJob extends btcdev.QueueableJob {
        public override void work() {
            insert new Account(Name = 'NS-MOCK-WORK-RAN');
        }

        public override void onFinalFailure(btcdev.Async.FailureContext failureCtx) {
            insert new Account(Name = 'NS-MOCK-FAILED', Description = failureCtx.failure?.message);
        }
    }

    @IsTest
    static void shouldFailAJobFromAQueueableMock() {
        btcdev.AsyncMock.whenQueueable('ns-mock-throw')
            .thenThrow(new NsMockException('mocked failure'));

        Test.startTest();
        btcdev.Async.queueable(new NeverFailingJob())
            .mockId('ns-mock-throw')
            .continueOnJobExecuteFail()
            .enqueue();
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Account WHERE Name = 'NS-MOCK-WORK-RAN'],
            'thenThrow replaces the job body, so work() never runs'
        );
        System.assertEquals(
            'mocked failure',
            [SELECT Description FROM Account WHERE Name = 'NS-MOCK-FAILED' LIMIT 1].Description,
            'A mocked failure settles through the same path a real one does'
        );
    }
}
