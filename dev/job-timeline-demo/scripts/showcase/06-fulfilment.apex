Account order = [SELECT Id FROM Account WHERE Name = 'Acme Order #00124' LIMIT 1];
Async.Result reserve = Async.queueable(new ReserveStockJob())
    .name('Reserve stock').chainName('Order fulfilment pipeline').linkRecord(order).chain();
Async.queueable(new CreateInvoiceJob()).name('Create invoice').linkRecord(order).chain();
Async.Result commission = Async.queueable(new CommissionSplitJob())
    .name('Commission split').linkRecord(order)
    .retry(1).backoff(Async.Backoff.fixed(1)).continueOnJobExecuteFail()
    .chain();
Async.Result rollups = Async.queueable(new AccountRollupJob()).name('Recalculate account rollups').linkRecord(order)
    .dependsOn(Async.after(commission).succeeded()).chain();
Async.queueable(new SyncToErpJob()).name('Sync to ERP').linkRecord(order)
    .dependsOn(Async.after(rollups).succeeded()).chain();
Async.queueable(new OrderStepJob()).name('Open support case').linkRecord(order)
    .dependsOn(Async.after(commission).failed()).chain();
Async.queueable(new OrderStepJob()).name('Notify sales team').linkRecord(order).chain();
Async.queueable().enqueue();
