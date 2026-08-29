public class StateJob extends btcdev.QueueableJob {
    public override void work() {
    }
}

btcdev.Async.Result ar1 = btcdev.Async.queueable(new StateJob()).chain();
btcdev.Async.QueueableChainState state1 = btcdev.Async.getCurrentQueueableChainState();

System.assertNotEquals(null, ar1);
System.assertNotEquals(null, state1);
System.assertNotEquals(null, state1.jobs);
System.assertEquals(1, state1.jobs.size());

btcdev.Async.Result ar2 = btcdev.Async.queueable(new StateJob()).chain();
btcdev.Async.QueueableChainState state2 = btcdev.Async.getCurrentQueueableChainState();

System.assertNotEquals(null, state2);
System.assertEquals(2, state2.jobs.size());

btcdev.Async.Result ar3 = btcdev.Async.queueable(new StateJob()).enqueue();

System.assertNotEquals(null, ar3);
System.assertNotEquals(null, ar3.salesforceJobId);
System.debug('PASS: ns-test-chain-state');
