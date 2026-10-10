/**
 * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
 *
 * v3.0.0
 **/
public class NsTestOptionsJob extends btcdev.QueueableJob {
    public String label;

    public NsTestOptionsJob(String label) {
        this.label = label;
    }

    public override void work() {
        System.debug('NsTestOptionsJob [' + label + '] executed!');
    }

    public override btcdev.QueueableJob cloneForDeepCopy() {
        return (btcdev.QueueableJob) JSON.deserialize(JSON.serialize(this), NsTestOptionsJob.class);
    }
}
