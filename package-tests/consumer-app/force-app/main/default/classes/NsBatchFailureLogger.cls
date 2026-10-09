/**
 * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
 *
 * v3.0.0
 **/
global class NsBatchFailureLogger implements btcdev.Async.OnJobFailed {
    public void onJobFailed(btcdev.Async.FailureContext ctx) {
        insert new Account(
            Name = 'NS-BATCH-LOGGED',
            Site = ctx.asyncType + '|' + ctx.batchPhase + '|' + ctx.batchScopeTruncated,
            Description = ctx.salesforceJobId + '|' + ctx.batchScope
        );
    }
}
