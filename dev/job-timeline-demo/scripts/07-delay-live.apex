Account order = [SELECT Id FROM Account WHERE Name = 'Northwind Order #10248' ORDER BY CreatedDate DESC LIMIT 1];
OrderStepJob reserve = new OrderStepJob();
OrderStepJob invoice = new OrderStepJob();
invoice.spinMs = 20000;
OrderStepJob rollups = new OrderStepJob();
OrderStepJob sync = new OrderStepJob();
Async.queueable(reserve).name('Reserve stock').chainName('Delays while you watch').linkRecord(order).delay(1)
    .chain(invoice).name('Create invoice').linkRecord(order)
    .chain(rollups).name('Recalculate rollups').linkRecord(order).delay(1)
    .chain(new TimelineDemoJobs.FailingJob('Payment gateway returned 502 Bad Gateway')).name('Commission split').linkRecord(order).continueOnJobExecuteFail()
    .chain(sync).name('Sync to ERP').linkRecord(order).delay(2)
    .enqueue();
