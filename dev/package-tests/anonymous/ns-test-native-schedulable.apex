public class NativeScheduleJob implements Schedulable {
    public void execute(SchedulableContext sc) {
    }
}

for (CronTrigger ct : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = 'NS_Test_Native_Schedulable']) {
    System.abortJob(ct.Id);
}

List<btcdev.Async.Result> results = btcdev.Async.schedulable(new NativeScheduleJob())
    .name('NS_Test_Native_Schedulable')
    .cronExpression(new btcdev.CronBuilder().everyDay(23, 57))
    .skipWhenAlreadyScheduled()
    .schedule();

System.assertNotEquals(null, results);
System.assert(!results.isEmpty());
for (btcdev.Async.Result r : results) {
    System.assertNotEquals(null, r.salesforceJobId);
    System.assertEquals(btcdev.Async.AsyncType.SCHEDULABLE, r.asyncType);
}

System.debug('PASS: ns-test-native-schedulable');
