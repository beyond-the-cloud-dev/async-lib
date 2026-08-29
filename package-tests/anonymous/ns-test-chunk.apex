// NsTestChunkJob is a deployed helper (package-tests/consumer-app) so its pages can be
// deserialized across async transactions - proves cloning of a real consumer ChunkJob.
public class ConsumerIdChunkJob extends btcdev.IdChunkJob {
    public override void work(Set<Id> ids) {
        System.debug('processing ids: ' + ids.size());
    }
}

// The scratch keeps records between runs, so names have to be unique per run for the
// bind-variable assertion below to mean anything.
String runMarker = 'Chunk NS ' + UUID.randomUUID().toString().left(8);

List<Account> accounts = new List<Account>();
for (Integer i = 0; i < 5; i++) {
    accounts.add(new Account(Name = runMarker + ' ' + i));
}
insert accounts;

btcdev.ChunkSource recordSource = btcdev.ChunkSource.of(accounts);
System.assertEquals(5, recordSource.getNumRecords(), 'In-memory source should report 5 records');
System.assertEquals(2, recordSource.fetch(0, 2).size(), 'Source should page 2 records');

btcdev.Async.Result recordRun = btcdev.Async.chunk(new NsTestChunkJob('ns-chunk-run'), recordSource)
    .chunkSize(2)
    .priority(5)
    .retry(1)
    .delayBetweenChunks(1)
    .enqueue();
System.assertNotEquals(null, recordRun);
System.assertNotEquals(null, recordRun.salesforceJobId);
System.assertEquals(btcdev.Async.AsyncType.QUEUEABLE, recordRun.asyncType);

btcdev.ChunkSource idSource = btcdev.ChunkSource.ofIds(new Map<Id, Account>(accounts).keySet());
btcdev.Async.Result idRun = btcdev.Async.chunk(new ConsumerIdChunkJob(), idSource)
    .chunkSize(2)
    .stopRemainingChunksOnFailure()
    .enqueue();
System.assertNotEquals(null, idRun.salesforceJobId);

btcdev.ChunkSource cursorSource = btcdev.ChunkSource.query('SELECT Id FROM Account');
System.assert(
    cursorSource.getNumRecords() >= 5,
    'Cursor source should report at least the inserted records'
);
btcdev.Async.Result cursorRun = btcdev.Async.chunk(new NsTestChunkJob('ns-cursor-run'), cursorSource)
    .chunkSize(2)
    .keepChunkPages()
    .enqueue();
System.assertNotEquals(null, cursorRun.salesforceJobId);

btcdev.Async.Result emptyRun = btcdev.Async.chunk(
        new NsTestChunkJob('empty'),
        btcdev.ChunkSource.of(new List<Account>())
    )
    .enqueue();
System.assertEquals(null, emptyRun.salesforceJobId, 'Empty source should enqueue nothing');

btcdev.ChunkSource boundSource = btcdev.ChunkSource.query(
    'SELECT Id FROM Account WHERE Name = :accountName',
    new Map<String, Object>{ 'accountName' => runMarker + ' 1' }
);
System.assertEquals(1, boundSource.getNumRecords(), 'Bind variables should reach the cursor');

btcdev.Async.Result chainedRun = btcdev.Async.queueable(new NsTestOptionsJob('ns-chunk-neighbour'))
    .chunk(new NsTestChunkJob('ns-chained-run'), btcdev.ChunkSource.of(accounts))
    .chunkSize(2)
    .chain(new NsTestOptionsJob('ns-chunk-neighbour'))
    .dependsOn(btcdev.Async.afterPrevious().finished())
    .enqueue();
System.assertNotEquals(
    null,
    chainedRun.salesforceJobId,
    'A chunk run should chain between ordinary jobs'
);

System.debug('PASS: ns-test-chunk');
