public class NsTestScheduleVerifyJob extends btcdev.QueueableJob {
    public override void work() {
        insert new Task(
            Subject = 'ScheduleVerify - ' + Datetime.now().formatGMT('yyyy-MM-dd HH:mm:ss'),
            Status = 'Completed',
            Priority = 'Low',
            Description = 'Created by NsTestScheduleVerifyJob to verify scheduled queueable execution.'
        );
    }
}
