public class ContextJob extends btcdev.QueueableJob {
    public override void work() {
        btcdev.Async.QueueableJobContext ctx = btcdev.Async.getQueueableJobContext();
        System.assertNotEquals(null, ctx);
        System.assertNotEquals(null, ctx.currentJob);
        System.assertNotEquals(null, ctx.currentJob.className);
        System.assertNotEquals(null, ctx.currentJob.customJobId);
        System.assertNotEquals(null, ctx.queueableCtx);
    }
}

btcdev.Async.Result ar = btcdev.Async.queueable(new ContextJob()).enqueue();

System.assertNotEquals(null, ar);
System.assertNotEquals(null, ar.salesforceJobId);
System.debug('PASS: ns-test-context (async assertions run when job executes)');
