/**
 * The chunk counterpart of BaseQueueableJob. Copy both when Async Lib is installed as a
 * namespaced package and you use restoreStateOnNextChunk() or restoreStateOnRetry().
 *
 * It is a separate file rather than an inner class because Apex rejects inner types inside inner
 * types, and btcdev.ChunkJob is top level anyway.
 *
 * Add `implements Database.AllowsCallouts` to any chunk job that calls out.
 **/
public abstract class BaseChunkJob extends btcdev.ChunkJob {
    public virtual override btcdev.QueueableJob cloneForDeepCopy() {
        return BaseQueueableJob.deepCopy(this);
    }
}
