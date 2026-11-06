for (CronTrigger ct : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = 'NS_Test_Batch_Schedule']) {
    System.abortJob(ct.Id);
}

List<btcdev.Async.Result> results = btcdev.Async.batchable(new NsTestBatch())
    .scopeSize(50)
    .asSchedulable()
    .name('NS_Test_Batch_Schedule')
    .cronExpression(new btcdev.CronBuilder().everyDay(23, 58))
    .skipWhenAlreadyScheduled()
    .schedule();

System.assertNotEquals(null, results);
System.assert(!results.isEmpty());
for (btcdev.Async.Result r : results) {
    System.assertNotEquals(null, r.salesforceJobId);
}

System.debug('PASS: ns-test-batch-schedule');
