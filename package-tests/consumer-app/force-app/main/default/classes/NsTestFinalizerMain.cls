/**
 * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
 *
 * v3.1.0
 **/
public class NsTestFinalizerMain extends btcdev.QueueableJob {
    public override void work() {
        System.debug('NsTestFinalizerMain executing...');
        btcdev.Async.queueable(new NsTestFinalizerHandler()).attachFinalizer();
        System.debug('NsTestFinalizerMain: finalizer attached successfully!');
    }
}
