/**
 * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
 *
 * v3.0.0
 **/
public class NsTestDeepCloneJob extends btcdev.QueueableJob {
    public String label;
    public Integer counter = 0;

    public NsTestDeepCloneJob(String label) {
        this.label = label;
    }

    public override void work() {
        System.debug('NsTestDeepCloneJob [' + label + '] counter=' + counter);
    }

    public override btcdev.QueueableJob cloneForDeepCopy() {
        return (btcdev.QueueableJob) JSON.deserialize(
            JSON.serialize(this),
            NsTestDeepCloneJob.class
        );
    }
}
