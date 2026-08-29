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
