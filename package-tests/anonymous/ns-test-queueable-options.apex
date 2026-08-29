btcdev.Async.Result ar1 = btcdev.Async.queueable(new NsTestOptionsJob('priority'))
    .priority(1)
    .enqueue();
System.assertNotEquals(null, ar1);
System.assertNotEquals(null, ar1.salesforceJobId);

btcdev.Async.Result ar2 = btcdev.Async.queueable(new NsTestOptionsJob('delay'))
    .delay(1)
    .enqueue();
System.assertNotEquals(null, ar2);
System.assertNotEquals(null, ar2.salesforceJobId);

btcdev.Async.Result ar3 = btcdev.Async.queueable(new NsTestOptionsJob('continueOnFail'))
    .continueOnJobExecuteFail()
    .continueOnJobEnqueueFail()
    .enqueue();
System.assertNotEquals(null, ar3);
System.assertNotEquals(null, ar3.salesforceJobId);

btcdev.Async.Result ar4 = btcdev.Async.queueable(new NsTestDeepCloneJob('deepClone'))
    .deepClone()
    .enqueue();
System.assertNotEquals(null, ar4);
System.assertNotEquals(null, ar4.salesforceJobId);

btcdev.Async.Result ar5 = btcdev.Async.queueable(new NsTestOptionsJob('rollback'))
    .rollbackOnJobExecuteFail()
    .enqueue();
System.assertNotEquals(null, ar5);
System.assertNotEquals(null, ar5.salesforceJobId);

System.debug('PASS: ns-test-queueable-options');
