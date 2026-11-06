btcdev.Async.Result ar = btcdev.Async.queueable(new NsTestFinalizerMain()).enqueue();

System.assertNotEquals(null, ar);
System.assertNotEquals(null, ar.salesforceJobId);
System.assertEquals(btcdev.Async.AsyncType.QUEUEABLE, ar.asyncType);
System.debug('PASS: ns-test-queueable-finalizer');
