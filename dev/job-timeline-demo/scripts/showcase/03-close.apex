Account order = [SELECT Id FROM Account WHERE Name = 'Acme Order #00124' LIMIT 1];
Async.queueable(new OrderStepJob()).name('Check open items').chainName('Month-end close').linkRecord(order)
    .chain(new StopOnClosedPeriodJob()).name('Verify period is open').linkRecord(order)
    .chain(new OrderStepJob()).name('Post journals').linkRecord(order)
    .chain(new OrderStepJob()).name('Lock books').linkRecord(order)
    .enqueue();
