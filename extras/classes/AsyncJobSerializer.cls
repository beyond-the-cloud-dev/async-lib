/**
 * Copy this when Async Lib is installed as a namespaced package and you use Async.requeue().
 * Register it once: QueueableJobSetting__mdt.JobSerializerClass__c = 'AsyncJobSerializer' on the
 * All record.
 *
 * JSON cannot cross a namespace boundary in either direction, so Async Lib can neither store nor
 * rebuild your job from inside its own namespace. Both halves run here instead, in yours.
 *
 * `global` is required. Async Lib resolves this class by name, and Type.forName reaches nothing
 * else across the boundary. The methods stay public.
 **/
global class AsyncJobSerializer implements btcdev.Async.JobSerializer {
    public String serialize(btcdev.QueueableJob job) {
        return JSON.serialize(job);
    }

    public btcdev.QueueableJob deserialize(String className, String payload) {
        return (btcdev.QueueableJob) JSON.deserialize(payload, Type.forName(className));
    }
}
