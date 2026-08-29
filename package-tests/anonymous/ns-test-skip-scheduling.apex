public class SkipTestJob extends btcdev.QueueableJob {
    public override void work() {
    }
}

for (CronTrigger ct : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = 'NS_Test_Skip_Schedule']) {
    System.abortJob(ct.Id);
}

List<btcdev.Async.Result> results1 = btcdev.Async.queueable(new SkipTestJob())
    .asSchedulable()
    .name('NS_Test_Skip_Schedule')
    .cronExpression(new btcdev.CronBuilder().everyDay(23, 56))
    .skipWhenAlreadyScheduled()
    .schedule();

System.assertNotEquals(null, results1);
System.assert(!results1.isEmpty());
System.assertNotEquals(null, results1[0].salesforceJobId);

List<btcdev.Async.Result> results2 = btcdev.Async.queueable(new SkipTestJob())
    .asSchedulable()
    .name('NS_Test_Skip_Schedule')
    .cronExpression(new btcdev.CronBuilder().everyDay(23, 56))
    .skipWhenAlreadyScheduled()
    .schedule();
System.assertNotEquals(null, results2);

Boolean caughtDuplicate = false;
try {
    btcdev.Async.queueable(new SkipTestJob())
        .asSchedulable()
        .name('NS_Test_Skip_Schedule')
        .cronExpression(new btcdev.CronBuilder().everyDay(23, 56))
        .schedule();
} catch (Exception e) {
    caughtDuplicate = true;
}
System.assert(caughtDuplicate, 'Should throw when scheduling duplicate name without skipWhenAlreadyScheduled');

System.debug('PASS: ns-test-skip-scheduling');
