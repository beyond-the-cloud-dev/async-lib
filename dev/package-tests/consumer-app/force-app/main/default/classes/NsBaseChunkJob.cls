/**
 * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
 *
 * v3.1.0
 *
 * Mirrors extras/classes/BaseChunkJob.cls so the class consumers are told to copy cannot rot
 * unnoticed. Any change to one belongs in the other.
 **/
public abstract class NsBaseChunkJob extends btcdev.ChunkJob {
    public virtual override btcdev.QueueableJob cloneForDeepCopy() {
        return NsBaseQueueableJob.deepCopy(this);
    }
}
