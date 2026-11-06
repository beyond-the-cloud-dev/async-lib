public class MassJob extends btcdev.QueueableJob {
    public Integer jobNumber;

    public MassJob(Integer jobNumber) {
        this.jobNumber = jobNumber;
    }

    public override void work() {
    }
}

for (Integer i = 0; i < 52; i++) {
    btcdev.Async.Result ar = btcdev.Async.queueable(new MassJob(i)).enqueue();
    System.assertNotEquals(null, ar);
}

Id schedulableId = btcdev.Async.getQueueableChainSchedulableId();
System.assertNotEquals(null, schedulableId, 'Overflow schedulable should exist after exceeding queueable limit');

System.debug('PASS: ns-test-mass-enqueue');
