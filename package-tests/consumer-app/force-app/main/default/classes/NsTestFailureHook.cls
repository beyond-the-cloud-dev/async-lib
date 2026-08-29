@IsTest
public class NsTestFailureHook {
    public class NsHookException extends Exception {
    }

    public class FailingHookJob extends btcdev.QueueableJob {
        public override void work() {
            throw new NsHookException('ns hook failure');
        }

        public override void onFinalFailure(btcdev.Async.FailureContext failureCtx) {
            insert new Account(
                Name = 'NS-HOOK',
                Description = failureCtx.retryOutcome.name() +
                    '|' +
                    (String.isBlank(failureCtx.failure?.stackTrace) ? 'NO-TRACE' : 'HAS-TRACE') +
                    '|' +
                    failureCtx.retryAttempt +
                    '/' +
                    failureCtx.maxRetries
            );
        }
    }

    public class SucceedingHookJob extends btcdev.QueueableJob {
        public override void work() {
            insert new Account(Name = 'NS-HOOK-RAN');
        }

        public override void onFinalFailure(btcdev.Async.FailureContext failureCtx) {
            insert new Account(Name = 'NS-HOOK');
        }
    }

    private static String hookDescription() {
        return [SELECT Description FROM Account WHERE Name = 'NS-HOOK' LIMIT 1].Description;
    }

    private static Integer hookCount() {
        return [SELECT COUNT() FROM Account WHERE Name = 'NS-HOOK'];
    }

    @IsTest
    static void shouldCallOverrideAcrossTheNamespaceBoundary() {
        Test.startTest();
        btcdev.Async.queueable(new FailingHookJob()).continueOnJobExecuteFail().enqueue();
        Test.stopTest();

        System.assertEquals(
            1,
            hookCount(),
            'Packaged framework must dispatch onFinalFailure into the subscriber subclass'
        );
        System.assertEquals('NOT_CONFIGURED|HAS-TRACE|0/0', hookDescription());
    }

    @IsTest
    static void shouldReportExhaustedAndFireOnlyOnce() {
        Test.startTest();
        btcdev.Async.queueable(new FailingHookJob()).continueOnJobExecuteFail().retry(2).enqueue();
        Test.stopTest();

        System.assertEquals(1, hookCount(), 'The hook fires once, not once per attempt');
        System.assertEquals('EXHAUSTED|HAS-TRACE|2/2', hookDescription());
    }

    @IsTest
    static void shouldReportNotRetryableWhenTypeIsExcluded() {
        Test.startTest();
        btcdev.Async.queueable(new FailingHookJob())
            .continueOnJobExecuteFail()
            .retry(2)
            .retryOn(DmlException.class)
            .enqueue();
        Test.stopTest();

        System.assertEquals('NOT_RETRYABLE|HAS-TRACE|0/2', hookDescription());
    }

    @IsTest
    static void shouldNotCallOverrideWhenJobSucceeds() {
        Test.startTest();
        btcdev.Async.queueable(new SucceedingHookJob()).enqueue();
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Account WHERE Name = 'NS-HOOK-RAN']);
        System.assertEquals(0, hookCount(), 'A job that succeeded never failed finally');
    }

    @IsTest
    static void shouldExposeEveryRetryOutcomeValue() {
        System.assertEquals(
            3,
            btcdev.Async.RetryOutcome.values().size(),
            'RetryOutcome must stay reachable and complete for consumers'
        );
        System.assertNotEquals(null, btcdev.Async.RetryOutcome.valueOf('NOT_CONFIGURED'));
        System.assertNotEquals(null, btcdev.Async.RetryOutcome.valueOf('NOT_RETRYABLE'));
        System.assertNotEquals(null, btcdev.Async.RetryOutcome.valueOf('EXHAUSTED'));
    }
}
