/**
 * Mirrors extras/classes/BaseChunkJob.cls so the class consumers are told to copy cannot rot
 * unnoticed. Any change to one belongs in the other.
 **/
public abstract class NsBaseChunkJob extends btcdev.ChunkJob {
    public virtual override btcdev.QueueableJob cloneForDeepCopy() {
        return NsBaseQueueableJob.deepCopy(this);
    }
}
