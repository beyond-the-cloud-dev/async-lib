/**
 * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
 *
 * v3.1.0
 **/
trigger AsyncBatchFailureTrigger on BatchApexErrorEvent(after insert) {
    BatchFailureRecorder.record(Trigger.new);
}
