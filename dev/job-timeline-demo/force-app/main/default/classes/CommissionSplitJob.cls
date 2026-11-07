/**
 * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
 *
 * v3.2.0
 **/
public class CommissionSplitJob extends QueueableJob implements Async.Retryable {
    public void resetBeforeRetry(Integer attempt) {
    }
    public override void work() {
        throw new DmlException(
            'UNABLE_TO_LOCK_ROW: unable to obtain exclusive access to this record. ' +
            'The commission split was rolled back.'
        );
    }
}
