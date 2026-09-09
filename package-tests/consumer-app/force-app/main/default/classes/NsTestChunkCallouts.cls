@IsTest
public class NsTestChunkCallouts {
    private static Integer pagesCalledOut = 0;
    private static Integer lastStatus = 0;

    private class OkCalloutMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            return response;
        }
    }

    public class CalloutChunkJob extends NsBaseChunkJob implements Database.AllowsCallouts, btcdev.Async.ChunkResettable {
        public List<String> seen = new List<String>();

        public override void work(List<SObject> page) {
            HttpRequest request = new HttpRequest();
            request.setEndpoint('https://example.com');
            request.setMethod('GET');
            NsTestChunkCallouts.lastStatus = new Http().send(request).getStatusCode();
            NsTestChunkCallouts.pagesCalledOut++;
            seen.add('page');
        }

        public void resetBeforeNextChunk(Integer pageNumber) {
        }
    }

    private static List<Account> inMemoryPages() {
        return new List<Account>{
            new Account(Name = 'a'),
            new Account(Name = 'b'),
            new Account(Name = 'c'),
            new Account(Name = 'd')
        };
    }

    @IsTest
    static void shouldCallOutFromEveryPageOfAPackagedChunkRun() {
        Test.setMock(HttpCalloutMock.class, new OkCalloutMock());

        Test.startTest();
        btcdev.Async.chunk(new CalloutChunkJob(), btcdev.ChunkSource.of(inMemoryPages()))
            .chunkSize(2)
            .enqueue();
        Test.stopTest();

        System.assertEquals(2, pagesCalledOut, 'Both pages must run');
        System.assertEquals(
            200,
            lastStatus,
            'A packaged chunk job marked Database.AllowsCallouts must be able to call out'
        );
    }

    @IsTest
    static void shouldCallOutFromEveryPageWhenPagesRestoreTheEnqueuedState() {
        Test.setMock(HttpCalloutMock.class, new OkCalloutMock());

        Test.startTest();
        btcdev.Async.chunk(new CalloutChunkJob(), btcdev.ChunkSource.of(inMemoryPages()))
            .chunkSize(2)
            .restoreStateOnNextChunk()
            .enqueue();
        Test.stopTest();

        System.assertEquals(
            2,
            pagesCalledOut,
            'Callout capability must survive the deep copy taken for the next page'
        );
    }

    @IsTest
    static void shouldKeepCalloutCapabilityThroughThePackagedDeepCopy() {
        CalloutChunkJob job = new CalloutChunkJob();
        job.deepClone = true;
        job.seen.add('before');

        btcdev.QueueableJob copy = job.cloneJob();

        System.assert(
            copy instanceof Database.AllowsCallouts,
            'The copy is the same concrete class, so it stays allowed to call out'
        );
        System.assertEquals(
            1,
            ((CalloutChunkJob) copy).seen.size(),
            'Subclass state must survive a deep copy taken through the base class'
        );
    }
}
