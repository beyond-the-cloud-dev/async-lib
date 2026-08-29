public class TestJob extends btcdev.QueueableJob {
    public override void work() {
    }
}

btcdev.Async.Result ar = btcdev.Async.queueable(new TestJob()).enqueue();

System.assertNotEquals(null, ar);
System.assertNotEquals(null, ar.salesforceJobId);
System.assertEquals(btcdev.Async.AsyncType.QUEUEABLE, ar.asyncType);
System.assertNotEquals(null, ar.customJobId);
System.assertNotEquals(null, ar.queueableChainState);
System.debug('PASS: ns-test-queueable-enqueue');
