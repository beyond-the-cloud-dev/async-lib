@IsTest
public class NsTestRetryBehavior {
    public class NsRetryException extends Exception {
    }

    public class HistoryCapturingJob extends btcdev.QueueableJob {
        public override void work() {
            throw new NsRetryException('ns retry failure');
        }

        public override void onFinalFailure(btcdev.Async.FailureContext failureCtx) {
            insert new Account(Name = 'NS-HISTORY', Description = failureCtx.retryHistory);
        }
    }

    public class MarkerFinalizer extends btcdev.QueueableJob.Finalizer {
        public override void work() {
            insert new Account(Name = 'NS-FINALIZER');
        }
    }

    public class FinalizerAttachingJob extends btcdev.QueueableJob {
        public override void work() {
            insert new Account(Name = 'NS-PARENT');
            btcdev.Async.queueable(new MarkerFinalizer()).attachFinalizer();
            throw new NsRetryException('ns retry failure');
        }
    }

    public class FollowUpJob extends btcdev.QueueableJob {
        public override void work() {
            insert new Account(Name = 'NS-FOLLOWUP');
        }
    }

    public class JobChainingJob extends btcdev.QueueableJob {
        public override void work() {
            insert new Account(Name = 'NS-PARENT');
            btcdev.Async.queueable(new FollowUpJob()).chain();
            throw new NsRetryException('ns retry failure');
        }
    }

    private static Integer countOf(String name) {
        return [SELECT COUNT() FROM Account WHERE Name = :name];
    }

    @IsTest
    static void shouldKeepEveryAttemptInRetryHistory() {
        Test.startTest();
        btcdev.Async.queueable(new HistoryCapturingJob())
            .continueOnJobExecuteFail()
            .retry(2)
            .enqueue();
        Test.stopTest();

        String history = [SELECT Description FROM Account WHERE Name = 'NS-HISTORY' LIMIT 1]
        .Description;
        for (String attempt : new List<String>{ 'Attempt 1', 'Attempt 2', 'Attempt 3' }) {
            System.assert(
                history.contains(attempt),
                'Retry history must carry ' + attempt + ' but was: ' + history
            );
        }
    }

    @IsTest
    static void shouldRunConsumerFinalizerOnceAcrossRetries() {
        Test.startTest();
        btcdev.Async.queueable(new FinalizerAttachingJob())
            .continueOnJobExecuteFail()
            .retry(2)
            .enqueue();
        Test.stopTest();

        System.assertEquals(3, countOf('NS-PARENT'), 'Original run plus 2 retries');
        System.assertEquals(
            1,
            countOf('NS-FINALIZER'),
            'A failed attempt must not leave its finalizer behind for the retry to duplicate'
        );
    }

    @IsTest
    static void shouldChainFollowUpJobOnceAcrossRetries() {
        Test.startTest();
        btcdev.Async.queueable(new JobChainingJob()).continueOnJobExecuteFail().retry(2).enqueue();
        Test.stopTest();

        System.assertEquals(3, countOf('NS-PARENT'), 'Original run plus 2 retries');
        System.assertEquals(
            1,
            countOf('NS-FOLLOWUP'),
            'A failed attempt must not leave its chained job behind for the retry to duplicate'
        );
    }
}
