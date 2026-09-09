/**
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
