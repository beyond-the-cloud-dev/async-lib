Account order = [SELECT Id FROM Account WHERE Name = 'Northwind Order #10248' ORDER BY CreatedDate DESC LIMIT 1];
OrderStepJob first = new OrderStepJob();
first.spinMs = 45000;
OrderStepJob second = new OrderStepJob();
second.spinMs = 45000;
Async.queueable(first).name('First step').chainName('Quick in flight check').linkRecord(order)
    .chain(second).name('Second step').linkRecord(order)
    .enqueue();
