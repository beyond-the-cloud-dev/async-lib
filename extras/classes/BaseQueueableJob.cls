/**
 * Copy this class into your own org when Async Lib is installed as a namespaced package.
 *
 * A deep copy has to serialize your job, and two Salesforce rules stop Async Lib doing that from
 * inside its own namespace: JSON.serialize refuses any object graph that crosses a namespace, and
 * Type.forName cannot resolve your classes from package code. Both rules are about where the code
 * runs, so running deepCopy() in your namespace satisfies them.
 *
 * Extend these instead of the btcdev equivalents and every job is covered, with no per-job
 * override. Add `implements Database.AllowsCallouts` to any job that calls out. Chunk jobs extend
 * BaseChunkJob. Rename anything to suit your project.
 **/
public abstract class BaseQueueableJob extends btcdev.QueueableJob {
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
            return BaseQueueableJob.deepCopy(this);
        }
    }
}
