public class PriorityJob extends btcdev.QueueableJob {
    public String label;

    public PriorityJob(String label) {
        this.label = label;
    }

    public override void work() {
    }
}

btcdev.Async.Result step1 = btcdev.Async.queueable(new PriorityJob('low'))
    .priority(10)
    .chain();
System.assertNotEquals(null, step1);

btcdev.Async.Result step2 = btcdev.Async.queueable(new PriorityJob('high'))
    .priority(1)
    .chain();
System.assertNotEquals(null, step2);

btcdev.Async.Result step3 = btcdev.Async.queueable(new PriorityJob('medium'))
    .priority(5)
    .chain();
System.assertNotEquals(null, step3);

btcdev.Async.QueueableChainState state = btcdev.Async.getCurrentQueueableChainState();
System.assertNotEquals(null, state);
System.assertNotEquals(null, state.jobs);
System.assertEquals(3, state.jobs.size());

btcdev.Async.Result result = btcdev.Async.queueable(new PriorityJob('final')).enqueue();
System.assertNotEquals(null, result);
System.assertNotEquals(null, result.salesforceJobId);
System.assertNotEquals(null, result.queueableChainState);
System.assertNotEquals(null, result.queueableChainState.jobs);

System.debug('PASS: ns-test-combined-flow');
