Account order = [SELECT Id FROM Account WHERE Name = 'Acme Order #00124' LIMIT 1];
Async.queueable(new OrderStepJob()).name('Collect invoices').chainName('Invoice export').linkRecord(order)
    .chain(new OrderStepJob()).name('Write export file').linkRecord(order)
    .chain(new OrderStepJob()).name('Send to accounting').linkRecord(order)
    .enqueue();
