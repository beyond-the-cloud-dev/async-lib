public class NsTestFinalizerMain extends btcdev.QueueableJob {
    public override void work() {
        System.debug('NsTestFinalizerMain executing...');
        btcdev.Async.queueable(new NsTestFinalizerHandler()).attachFinalizer();
        System.debug('NsTestFinalizerMain: finalizer attached successfully!');
    }
}
