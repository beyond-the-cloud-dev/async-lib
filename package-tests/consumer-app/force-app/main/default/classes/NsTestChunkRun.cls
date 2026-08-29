@IsTest
public class NsTestChunkRun {
    public class NsChunkException extends Exception {
    }

    public class MarkingChunkJob extends btcdev.ChunkJob {
        public override void work(List<SObject> chunk) {
            List<Account> toUpdate = new List<Account>();
            for (SObject record : chunk) {
                toUpdate.add(new Account(Id = record.Id, Site = 'PAGED'));
            }
            update toUpdate;
        }
    }

    public class TotallingChunkJob extends btcdev.ChunkJob {
        public Integer seen = 0;

        public override void work(List<SObject> chunk) {
            seen += chunk.size();
            insert new Account(Name = 'NS-RUNNING-TOTAL', Site = String.valueOf(seen));
        }
    }

    public class FailingChunkJob extends btcdev.ChunkJob {
        public override void work(List<SObject> chunk) {
            throw new NsChunkException('ns chunk failure');
        }

        public override void onFinalFailure(btcdev.Async.FailureContext failureCtx) {
            insert new Account(Name = 'NS-PAGE-FAILED');
        }
    }

    private static List<Account> sourceAccounts(Integer howMany) {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < howMany; i++) {
            accounts.add(new Account(Name = 'NS Chunk Source ' + i));
        }
        insert accounts;
        return accounts;
    }

    @IsTest
    static void shouldProcessEveryRecordAcrossPages() {
        List<Account> accounts = sourceAccounts(5);

        Test.startTest();
        btcdev.Async.chunk(new MarkingChunkJob(), btcdev.ChunkSource.of(accounts))
            .chunkSize(2)
            .enqueue();
        Test.stopTest();

        System.assertEquals(
            5,
            [SELECT COUNT() FROM Account WHERE Site = 'PAGED'],
            'Every record must be processed, not just the first page'
        );
    }

    @IsTest
    static void shouldCarryJobStateBetweenPages() {
        List<Account> accounts = sourceAccounts(6);

        Test.startTest();
        btcdev.Async.chunk(new TotallingChunkJob(), btcdev.ChunkSource.of(accounts))
            .chunkSize(2)
            .enqueue();
        Test.stopTest();

        Set<String> totals = new Set<String>();
        for (Account marker : [SELECT Site FROM Account WHERE Name = 'NS-RUNNING-TOTAL']) {
            totals.add(marker.Site);
        }
        System.assertEquals(
            new Set<String>{ '2', '4', '6' },
            totals,
            'Member state must accumulate across pages, not reset each hop'
        );
    }

    @IsTest
    static void shouldCallFailureHookForEveryFailedPage() {
        List<Account> accounts = sourceAccounts(4);

        Test.startTest();
        btcdev.Async.chunk(new FailingChunkJob(), btcdev.ChunkSource.of(accounts))
            .chunkSize(2)
            .enqueue();
        Test.stopTest();

        System.assertEquals(
            2,
            [SELECT COUNT() FROM Account WHERE Name = 'NS-PAGE-FAILED'],
            'Each failed page is its own final failure'
        );
    }

    @IsTest
    static void shouldStopRemainingPagesOnFailure() {
        List<Account> accounts = sourceAccounts(6);

        Test.startTest();
        btcdev.Async.chunk(new FailingChunkJob(), btcdev.ChunkSource.of(accounts))
            .chunkSize(2)
            .stopRemainingChunksOnFailure()
            .enqueue();
        Test.stopTest();

        System.assertEquals(
            1,
            [SELECT COUNT() FROM Account WHERE Name = 'NS-PAGE-FAILED'],
            'The run halts after the first failed page instead of working through all three'
        );
    }

    @IsTest
    static void shouldRejectChunkSizeAboveTheCursorCap() {
        Boolean rejected = false;
        try {
            btcdev.Async.chunk(
                    new MarkingChunkJob(),
                    btcdev.ChunkSource.query('SELECT Id FROM Account')
                )
                .chunkSize(2001);
        } catch (Exception ex) {
            rejected = true;
        }
        System.assert(rejected, 'A cursor source must reject a chunkSize above the 2000 fetch cap');
    }
}
