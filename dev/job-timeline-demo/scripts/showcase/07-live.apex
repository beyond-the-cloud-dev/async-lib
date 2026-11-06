Account order = [SELECT Id FROM Account WHERE Name = 'Acme Order #00124' LIMIT 1];
OrderStepJob a = new OrderStepJob();
a.spinMs = 4000;
OrderStepJob b = new OrderStepJob();
b.spinMs = 6000;
ReserveStockJob c = new ReserveStockJob();
c.spinMs = 8000;
CreateInvoiceJob d = new CreateInvoiceJob();
d.spinMs = 8000;
List<Account> lines = [SELECT Id FROM Account WHERE Name LIKE 'Line %' ORDER BY Name LIMIT 16];
AccountRollupJob e = new AccountRollupJob();
e.spinMs = 8000;
SyncToErpJob f = new SyncToErpJob();
f.spinMs = 8000;
Async.queueable(a).name('Validate order').chainName('Order approval pipeline').linkRecord(order)
    .chain(b).name('Credit check').linkRecord(order)
    .chain(c).name('Reserve stock').linkRecord(order)
    .chain(d).name('Create invoice').linkRecord(order)
    .chunk(new OrderPagesJob(), ChunkSource.of(lines)).chunkSize(2).name('Tax 16 lines').linkRecord(order)
    .chain(e).name('Recalculate account rollups').linkRecord(order)
    .chain(f).name('Sync to ERP').linkRecord(order)
    .enqueue();
