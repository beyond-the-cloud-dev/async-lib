/**
 * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
 *
 * v3.1.0
 **/
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
