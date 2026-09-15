@IsTest
public class NsTestRequeue {
    public class NsRequeueException extends Exception {
    }

    public class ReplayableJob extends btcdev.QueueableJob {
        public String tag;

        public ReplayableJob() {
        }

        public ReplayableJob(String tag) {
            this.tag = tag;
        }

        public override void work() {
            insert new Account(Name = 'NS-REPLAY-RAN', Description = tag);
            throw new NsRequeueException('ns requeue failure');
        }
    }

    private static void storePayloadsWithoutResults() {
        btcdev.AsyncMock.jobSettings(
            new List<btcdev__QueueableJobSetting__mdt>{
                new btcdev__QueueableJobSetting__mdt(
                    btcdev__QueueableJobName__c = 'All',
                    btcdev__StoreJobPayload__c = 'Yes',
                    btcdev__JobSerializerClass__c = 'NsJobSerializer'
                )
            }
        );
    }

    private static btcdev__AsyncResult__c failedResult() {
        return [
            SELECT
                Id,
                btcdev__Status__c,
                btcdev__RequeueStatus__c,
                btcdev__PayloadSize__c,
                btcdev__JobPayload__c
            FROM btcdev__AsyncResult__c
            LIMIT 1
        ];
    }

    @IsTest
    static void shouldStoreAPayloadWithoutTurningOnRoutineResultRows() {
        storePayloadsWithoutResults();

        Test.startTest();
        btcdev.Async.queueable(new ReplayableJob('NS-FIRST-RUN'))
            .continueOnJobExecuteFail()
            .enqueue();
        Test.stopTest();

        btcdev__AsyncResult__c stored = failedResult();
        System.assertEquals(
            'FAILED',
            stored.btcdev__Status__c,
            'A failure row has to be written even with Create Result off, or the payload is unreachable'
        );
        System.assertEquals('Stored', stored.btcdev__RequeueStatus__c);
        System.assert(
            stored.btcdev__JobPayload__c.contains('NS-FIRST-RUN'),
            'The payload must carry the state the job was enqueued with, but was: ' +
            stored.btcdev__JobPayload__c
        );
        System.assertEquals(
            stored.btcdev__JobPayload__c.length(),
            stored.btcdev__PayloadSize__c,
            'The size has to be filterable, because the payload field is not'
        );
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Account WHERE Name = 'NS-SERIALIZE'],
            'Capture has to run through the registered serializer, in the subscriber namespace'
        );
    }

    @IsTest
    static void shouldRebuildAStoredJobThroughTheRegisteredSerializer() {
        storePayloadsWithoutResults();

        Test.startTest();
        btcdev.Async.queueable(new ReplayableJob('NS-FIRST-RUN'))
            .continueOnJobExecuteFail()
            .enqueue();
        Test.stopTest();

        btcdev__AsyncResult__c stored = failedResult();
        btcdev.Async.RequeueSummary summary = btcdev.Async.requeue(stored.Id);

        System.assertEquals(
            new List<Id>{ stored.Id },
            summary.requeued,
            'The stored result has to be replayable from consumer code'
        );
        System.assert(
            summary.skipReasonByResultId.isEmpty(),
            'Nothing should have been skipped, but was: ' + summary.skipReasonByResultId
        );
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Account WHERE Name = 'NS-DESERIALIZE'],
            'Rebuild has to run through the registered serializer, in the subscriber namespace'
        );
        System.assertEquals(
            'Requeued',
            [
                SELECT btcdev__RequeueStatus__c
                FROM btcdev__AsyncResult__c
                WHERE Id = :stored.Id
            ]
            .btcdev__RequeueStatus__c,
            'Marking the source is what stops a scheduled replay picking it up twice'
        );
    }

    @IsTest
    static void shouldExplainAResultThatHasNothingToReplay() {
        btcdev__AsyncResult__c noPayload = new btcdev__AsyncResult__c(btcdev__Status__c = 'FAILED');
        insert noPayload;

        btcdev.Async.RequeueSummary summary = btcdev.Async.requeue(noPayload.Id);

        System.assert(summary.requeued.isEmpty(), 'There is nothing to replay');
        System.assert(
            summary.skipReasonByResultId.get(noPayload.Id).contains('StoreJobPayload__c'),
            'The reason has to name the setting to turn on, but was: ' +
            summary.skipReasonByResultId.get(noPayload.Id)
        );
    }
}
