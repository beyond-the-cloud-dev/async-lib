Account order = [SELECT Id FROM Account WHERE Name = 'Acme Order #00124' LIMIT 1];
OrderStepJob first = new OrderStepJob();
first.spinMs = 200;
QueueableBuilder chain = Async.queueable(first).name('Load warehouse 1').chainName('Nightly stock sync').linkRecord(order);
for (Integer i = 2; i <= 24; i++) {
    OrderStepJob next = new OrderStepJob();
    next.spinMs = 200;
    chain = chain.chain(next).name('Load warehouse ' + i).linkRecord(order);
}
chain.enqueue();
