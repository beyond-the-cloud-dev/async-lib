Account order = [SELECT Id FROM Account WHERE Name = 'Acme Order #00124' LIMIT 1];
List<Account> lines = [SELECT Id FROM Account WHERE Name LIKE 'Line %' ORDER BY Name LIMIT 12];
Async.queueable(new OrderStepJob()).name('Prepare order').chainName('Order sync').linkRecord(order)
    .chunk(new OrderPagesJob(), ChunkSource.of(lines)).chunkSize(2)
        .name('Tax 12 lines').linkRecord(order)
    .chain(new AccountRollupJob()).name('Reconcile totals').linkRecord(order)
    .chain(new SyncToErpJob()).name('Publish to ERP').linkRecord(order)
    .enqueue();
