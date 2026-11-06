Account order = [SELECT Id FROM Account WHERE Name = 'Northwind Order #10248' ORDER BY CreatedDate DESC LIMIT 1];
List<Account> lines = [SELECT Id FROM Account WHERE Name LIKE 'Line %' ORDER BY Name LIMIT 16];
PriorityDemoJob first = new PriorityDemoJob();
first.spinMs = 30000;
first.addsJobsLinkedTo = order.Id;
PriorityDemoJob last = new PriorityDemoJob();
last.spinMs = 8000;
Async.queueable(first).name('Adds two jobs after 30 s').chainName('Jobs added while you watch').linkRecord(order)
    .chunk(new OrderPagesJob(), ChunkSource.of(lines)).chunkSize(2).name('Tax 16 lines').linkRecord(order)
    .chain(last).name('Sync to ERP').linkRecord(order)
    .enqueue();
