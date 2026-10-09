/**
 * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
 *
 * v3.0.0
 *
 * Mirrors extras/classes/BaseQueueableJob.cls so the class consumers are told to copy cannot rot
 * unnoticed. Any change to one belongs in the other.
 **/
public abstract class NsBaseQueueableJob extends btcdev.QueueableJob {
    public static btcdev.QueueableJob deepCopy(btcdev.QueueableJob job) {
        return (btcdev.QueueableJob) JSON.deserialize(
            JSON.serialize(job),
            Type.forName(job.className)
        );
    }

    public virtual override btcdev.QueueableJob cloneForDeepCopy() {
        return deepCopy(this);
    }

    public abstract class Finalizer extends btcdev.QueueableJob.Finalizer {
        public virtual override btcdev.QueueableJob cloneForDeepCopy() {
            return NsBaseQueueableJob.deepCopy(this);
        }
    }
}
