Account order = [SELECT Id FROM Account WHERE Name = 'Acme Order #00124' LIMIT 1];
List<Account> lines = [SELECT Id FROM Account WHERE Name LIKE 'Line %' ORDER BY Name LIMIT 24];
Async.chunk(new RepriceLinesJob(), ChunkSource.of(lines)).chunkSize(3)
    .name('Reprice 24 lines').chainName('Reprice order lines').linkRecord(order).enqueue();
