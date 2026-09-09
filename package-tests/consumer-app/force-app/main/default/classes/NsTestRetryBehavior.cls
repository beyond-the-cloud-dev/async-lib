@IsTest
public class NsTestRetryBehavior {
    public class NsRetryException extends Exception {
    }

    public class HistoryCapturingJob extends btcdev.QueueableJob implements btcdev.Async.Retryable {
        public void resetBeforeRetry(Integer attempt) {
        }

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

    public class FinalizerAttachingJob extends btcdev.QueueableJob implements btcdev.Async.Retryable {
        public void resetBeforeRetry(Integer attempt) {
        }

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

    public class JobChainingJob extends btcdev.QueueableJob implements btcdev.Async.Retryable {
        public void resetBeforeRetry(Integer attempt) {
        }

        public override void work() {
            insert new Account(Name = 'NS-PARENT');
            btcdev.Async.queueable(new FollowUpJob()).chain();
            throw new NsRetryException('ns retry failure');
        }
    }

    public class DeepCloneRetryJob extends btcdev.QueueableJob implements btcdev.Async.Retryable {
        public List<String> attempts = new List<String>();

        public void resetBeforeRetry(Integer attempt) {
        }

        public override void work() {
            attempts.add('attempt');
            insert new Account(Name = 'NS-DEEPCLONE-RETRY');
            throw new NsRetryException('ns retry failure');
        }

        public override btcdev.QueueableJob cloneForDeepCopy() {
            return (btcdev.QueueableJob) JSON.deserialize(
                JSON.serialize(this),
                DeepCloneRetryJob.class
            );
        }
    }

    public class UngatedNsJob extends btcdev.QueueableJob {
        public override void work() {
        }
    }

    public class UngatedNsChunkJob extends btcdev.ChunkJob {
        public override void work(List<SObject> page) {
        }
    }

    public class RestoringNsJob extends NsBaseQueueableJob {
        public List<String> seen = new List<String>();

        public override void work() {
            insert new Account(Name = 'NS-RESTORE-' + seen.size());
            seen.add('attempt');
            throw new NsRetryException('ns retry failure');
        }
    }

    public class RestoringNsChunkJob extends NsBaseChunkJob {
        public List<String> seen = new List<String>();

        public override void work(List<SObject> page) {
            insert new Account(Name = 'NS-CHUNK-RESTORE-' + seen.size());
            seen.add('page');
        }
    }

    private static Integer countOf(String name) {
        return [SELECT COUNT() FROM Account WHERE Name = :name];
    }

    private static List<Account> nsAccounts(Integer howMany) {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < howMany; i++) {
            accounts.add(new Account(Name = 'NS-SOURCE-' + i));
        }
        insert accounts;
        return accounts;
    }

    @IsTest
    static void shouldStopAConsumerRetryJobThatNeverDeclaresItsReset() {
        try {
            btcdev.Async.queueable(new UngatedNsJob()).retry(2).enqueue();
            System.assert(false, 'The gate must reject a consumer job with no declared reset');
        } catch (Exception ex) {
            System.assert(
                ex.getMessage().contains('btcdev.Async.Retryable'),
                'A packaged consumer must be told the namespaced type name, but was: ' +
                ex.getMessage()
            );
        }
    }

    @IsTest
    static void shouldStopAConsumerChunkJobThatNeverDeclaresItsReset() {
        try {
            btcdev.Async.chunk(new UngatedNsChunkJob(), btcdev.ChunkSource.of(nsAccounts(2)))
                .enqueue();
            System.assert(
                false,
                'The gate must reject a consumer chunk job with no declared reset'
            );
        } catch (Exception ex) {
            System.assert(
                ex.getMessage().contains('btcdev.Async.ChunkResettable'),
                'A packaged consumer must be told the namespaced type name, but was: ' +
                ex.getMessage()
            );
        }
    }

    @IsTest
    static void shouldRestoreTheEnqueuedStateOnRetryFromASubscriberNamespace() {
        Test.startTest();
        btcdev.Async.queueable(new RestoringNsJob())
            .restoreStateOnRetry()
            .continueOnJobExecuteFail()
            .retry(2)
            .enqueue();
        Test.stopTest();

        System.assertEquals(
            3,
            countOf('NS-RESTORE-0'),
            'Every attempt must replay from the enqueue-time copy taken through the base class'
        );
    }

    @IsTest
    static void shouldRestoreTheEnqueuedStateOnEveryChunkPageFromASubscriberNamespace() {
        Test.startTest();
        btcdev.Async.chunk(new RestoringNsChunkJob(), btcdev.ChunkSource.of(nsAccounts(6)))
            .chunkSize(2)
            .restoreStateOnNextChunk()
            .enqueue();
        Test.stopTest();

        System.assertEquals(
            3,
            countOf('NS-CHUNK-RESTORE-0'),
            'A packaged ChunkJob must deep copy without the ChunkSource blocking it'
        );
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

    public class AsyncLibTypeHoldingJob extends btcdev.QueueableJob {
        public btcdev.Async.Result heldResult;
        public btcdev.Backoff heldBackoff;
        public btcdev.Async.Dependency heldDependency;

        public override void work() {
            insert new Account(Name = 'NS-HELD-TYPES');
        }

        public override btcdev.QueueableJob cloneForDeepCopy() {
            return (btcdev.QueueableJob) JSON.deserialize(
                JSON.serialize(this),
                AsyncLibTypeHoldingJob.class
            );
        }
    }

    public class InheritedCloneJobA extends NsBaseQueueableJob implements btcdev.Async.Retryable {
        public List<String> attempts = new List<String>();

        public void resetBeforeRetry(Integer attempt) {
        }

        public override void work() {
            attempts.add('a');
            insert new Account(Name = 'NS-INHERITED-A-' + retryAttempt);
            throw new NsRetryException('ns retry failure');
        }
    }

    public class InheritedCloneJobB extends NsBaseQueueableJob {
        public String label = 'b';
        public override void work() {
            insert new Account(Name = 'NS-INHERITED-B');
        }
    }

    public class InheritedCalloutJob extends NsBaseQueueableJob implements Database.AllowsCallouts {
        public String label = 'default';
        public List<String> items = new List<String>();
        public override void work() {
            insert new Account(Name = 'NS-INHERITED-CALLOUT');
        }
    }

    public class InheritedFinalizerJob extends NsBaseQueueableJob.Finalizer {
        public override void work() {
            insert new Account(Name = 'NS-INHERITED-FINALIZER');
        }
    }

    @IsTest
    static void shouldKeepJobCapabilitiesAndStateThroughAnInheritedDeepClone() {
        InheritedCalloutJob calloutJob = new InheritedCalloutJob();
        calloutJob.deepClone = true;
        calloutJob.label = 'CHANGED';
        calloutJob.items = new List<String>{ 'a', 'b' };

        btcdev.QueueableJob copy = calloutJob.cloneJob();
        InheritedCalloutJob calloutCopy = (InheritedCalloutJob) copy;

        System.assert(
            copy instanceof Database.AllowsCallouts,
            'A retried callout job must still be allowed to call out'
        );
        System.assertEquals('CHANGED', calloutCopy.label, 'Subclass state must survive the clone');
        System.assertEquals(2, calloutCopy.items.size(), 'Subclass collections must survive');

        calloutJob.items.add('AFTER-CLONE');
        System.assertEquals(
            2,
            calloutCopy.items.size(),
            'The copy must be isolated from the source'
        );

        InheritedFinalizerJob finalizerJob = new InheritedFinalizerJob();
        finalizerJob.deepClone = true;

        System.assert(
            finalizerJob.cloneJob() instanceof btcdev.QueueableJob.Finalizer,
            'A cloned finalizer must stay recognisable to the framework'
        );
    }

    @IsTest
    static void shouldDeepCloneEveryJobSharingOneBaseClassOverride() {
        Test.startTest();
        btcdev.Async.queueable(new InheritedCloneJobA())
            .deepClone()
            .continueOnJobExecuteFail()
            .retry(2)
            .enqueue();
        btcdev.Async.queueable(new InheritedCloneJobB()).deepClone().enqueue();
        Test.stopTest();

        System.assertEquals(
            3,
            countOf('NS-INHERITED-A-0') + countOf('NS-INHERITED-A-1') + countOf('NS-INHERITED-A-2'),
            'One shared cloneForDeepCopy() must serve retries of any subclass'
        );
        System.assertEquals(
            1,
            countOf('NS-INHERITED-B'),
            'The same base class must serve a second, unrelated subclass'
        );
    }

    @IsTest
    static void shouldDeepCloneAJobHoldingAsyncLibTypes() {
        AsyncLibTypeHoldingJob job = new AsyncLibTypeHoldingJob();
        job.heldBackoff = btcdev.Async.Backoff.fixed(1);
        job.heldDependency = btcdev.Async.afterPrevious().succeeded();

        Test.startTest();
        btcdev.Async.queueable(job).deepClone().enqueue();
        Test.stopTest();

        System.assertEquals(
            1,
            countOf('NS-HELD-TYPES'),
            'A consumer job holding Async Lib types must still be deep cloneable'
        );
    }

    @IsTest
    static void shouldRetryADeepClonedJob() {
        Test.startTest();
        btcdev.Async.queueable(new DeepCloneRetryJob())
            .deepClone()
            .continueOnJobExecuteFail()
            .retry(2)
            .enqueue();
        Test.stopTest();

        System.assertEquals(
            3,
            countOf('NS-DEEPCLONE-RETRY'),
            'deepClone() must not silently disable retry: original run plus 2 retries'
        );
    }
}
