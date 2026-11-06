public class ScheduleTestJob extends btcdev.QueueableJob {
    public override void work() {
    }
}

for (CronTrigger ct : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = 'NS_Test_Schedule']) {
    System.abortJob(ct.Id);
}

List<btcdev.Async.Result> results = btcdev.Async.queueable(new ScheduleTestJob())
    .asSchedulable()
    .name('NS_Test_Schedule')
    .cronExpression(new btcdev.CronBuilder().everyDay(23, 59))
    .skipWhenAlreadyScheduled()
    .schedule();

System.assertNotEquals(null, results);
System.assert(!results.isEmpty());
for (btcdev.Async.Result r : results) {
    System.assertNotEquals(null, r.salesforceJobId);
    System.assertEquals(btcdev.Async.AsyncType.SCHEDULABLE, r.asyncType);
}

System.debug('PASS: ns-test-schedulable');
