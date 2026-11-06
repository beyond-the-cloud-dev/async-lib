public class CalloutJob extends btcdev.QueueableJob.AllowsCallouts {
    public override void work() {
    }
}

btcdev.Async.Result ar = btcdev.Async.queueable(new CalloutJob()).enqueue();

System.assertNotEquals(null, ar);
System.assertNotEquals(null, ar.salesforceJobId);
System.assertEquals(btcdev.Async.AsyncType.QUEUEABLE, ar.asyncType);
System.debug('PASS: ns-test-queueable-callouts');
