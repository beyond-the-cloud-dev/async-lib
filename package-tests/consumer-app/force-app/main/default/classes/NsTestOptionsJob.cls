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
