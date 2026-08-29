public class NsTestFinalizerHandler extends btcdev.QueueableJob.Finalizer {
    public override void work() {
        btcdev.Async.QueueableJobContext ctx = btcdev.Async.getQueueableJobContext();
        System.debug('NsTestFinalizerHandler executing!');
        System.debug('Is Finalizer: ' + this.isFinalizer);
        System.debug('Parent Custom Job Id: ' + this.parentCustomJobId);
        if (ctx.finalizerCtx != null) {
            System.debug('Finalizer Result: ' + ctx.finalizerCtx.getResult());
        }
    }
}
