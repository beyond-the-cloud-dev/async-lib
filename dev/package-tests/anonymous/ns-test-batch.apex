btcdev.Async.Result ar = btcdev.Async.batchable(new NsTestBatch())
    .scopeSize(100)
    .execute();

System.assertNotEquals(null, ar);
System.assertNotEquals(null, ar.salesforceJobId);
System.assertEquals(btcdev.Async.AsyncType.BATCHABLE, ar.asyncType);
System.debug('PASS: ns-test-batch');
