for (CronTrigger ct : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = 'NS_Test_Cleanup']) {
    System.abortJob(ct.Id);
}

List<btcdev.Async.Result> scheduled = btcdev.Async.batchable(
        new btcdev.AsyncResultCleanupBatch().failedOlderThanDays(90).othersOlderThanDays(30)
    )
    .asSchedulable()
    .name('NS_Test_Cleanup')
    .cronExpression(new btcdev.CronBuilder().everyDay(3, 0))
    .schedule();
System.assertEquals(1, scheduled.size(), 'The packaged cleanup batch schedules like the docs say.');
for (CronTrigger ct : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = 'NS_Test_Cleanup']) {
    System.abortJob(ct.Id);
}

btcdev.Async.Result ran = btcdev.Async.batchable(
        new btcdev.AsyncResultCleanupBatch().othersOlderThanDays(30)
    )
    .scopeSize(2000)
    .execute();
System.assertNotEquals(null, ran.salesforceJobId, 'The ad hoc run enqueues.');

try {
    new btcdev.AsyncResultCleanupBatch().failedOlderThanDays(0);
    System.assert(false, 'zero days must throw');
} catch (Exception expected) {
    System.assert(expected.getMessage().contains('greater than zero'), expected.getMessage());
}

System.debug('PASS: ns-test-cleanup');
