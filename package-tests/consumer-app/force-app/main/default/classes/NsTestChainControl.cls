@IsTest
public class NsTestChainControl {
    public class NsChainException extends Exception {
    }

    public class MarkerJob extends btcdev.QueueableJob {
        public String tag;
        public Boolean shouldFail = false;

        public MarkerJob(String tag, Boolean shouldFail) {
            this.tag = tag;
            this.shouldFail = shouldFail;
        }

        public override void work() {
            insert new Account(Name = tag);
            if (shouldFail) {
                throw new NsChainException('ns chain failure');
            }
        }
    }

    public class ChainStoppingJob extends btcdev.QueueableJob {
        public override void work() {
            insert new Account(Name = 'NS-STOPPER');
            btcdev.Async.stopChain();
        }
    }

    private static Integer countOf(String name) {
        return [SELECT COUNT() FROM Account WHERE Name = :name];
    }

    @IsTest
    static void shouldGateChainOnDependencyOutcome() {
        Test.startTest();
        btcdev.Async.Result gate = btcdev.Async.queueable(new MarkerJob('NS-GATE', true))
            .continueOnJobExecuteFail()
            .chain();
        btcdev.Async.queueable(new MarkerJob('NS-ON-SUCCESS', false))
            .dependsOn(btcdev.Async.after(gate).succeeded())
            .chain();
        btcdev.Async.queueable(new MarkerJob('NS-ON-FAILURE', false))
            .dependsOn(btcdev.Async.after(gate).failed())
            .enqueue();
        Test.stopTest();

        System.assertEquals(1, countOf('NS-GATE'), 'The gate ran and failed');
        System.assertEquals(0, countOf('NS-ON-SUCCESS'), 'Skipped because the gate failed');
        System.assertEquals(1, countOf('NS-ON-FAILURE'), 'Ran as the compensation path');
    }

    @IsTest
    static void shouldStopEverythingAfterStopChain() {
        Test.startTest();
        btcdev.Async.queueable(new ChainStoppingJob()).chain();
        btcdev.Async.queueable(new MarkerJob('NS-AFTER-STOP', false)).enqueue();
        Test.stopTest();

        System.assertEquals(1, countOf('NS-STOPPER'));
        System.assertEquals(0, countOf('NS-AFTER-STOP'), 'stopChain must stop the whole chain');
    }

    @IsTest
    static void shouldRunJobsInPriorityOrder() {
        Test.startTest();
        btcdev.Async.queueable(new MarkerJob('NS-LOW', false)).priority(10).chain();
        btcdev.Async.queueable(new MarkerJob('NS-HIGH', false)).priority(1).enqueue();
        Test.stopTest();

        List<Account> ordered = [
            SELECT Name
            FROM Account
            WHERE Name IN ('NS-LOW', 'NS-HIGH')
            ORDER BY CreatedDate ASC, Id ASC
        ];
        System.assertEquals(2, ordered.size(), 'Both jobs ran');
        System.assertEquals('NS-HIGH', ordered[0].Name, 'Lower priority number runs first');
    }

    @IsTest
    static void shouldAcceptAsyncOptions() {
        AsyncOptions options = new AsyncOptions();
        options.MaximumQueueableStackDepth = 5;

        Test.startTest();
        btcdev.Async.Result result = btcdev.Async.queueable(new MarkerJob('NS-OPTIONS', false))
            .asyncOptions(options)
            .enqueue();
        Test.stopTest();

        System.assertNotEquals(null, result.customJobId, 'asyncOptions must not break enqueue');
        System.assertEquals(1, countOf('NS-OPTIONS'), 'The job still runs with AsyncOptions set');
    }

    @IsTest
    static void shouldSkipJobByCustomJobId() {
        Test.startTest();
        btcdev.Async.Result first = btcdev.Async.queueable(new MarkerJob('NS-KEEP', false)).chain();
        btcdev.Async.Result second = btcdev.Async.queueable(new MarkerJob('NS-SKIPPED', false))
            .chain();
        btcdev.Async.skipJob(second.customJobId);
        btcdev.Async.queueable(new MarkerJob('NS-LAST', false)).enqueue();
        Test.stopTest();

        System.assertEquals(1, countOf('NS-KEEP'));
        System.assertEquals(0, countOf('NS-SKIPPED'), 'An explicitly skipped job must not run');
        System.assertEquals(1, countOf('NS-LAST'), 'The rest of the chain still runs');
    }
}
