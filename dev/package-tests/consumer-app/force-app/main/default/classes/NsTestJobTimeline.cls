/**
 * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
 *
 * v3.1.0
 **/
@IsTest
public class NsTestJobTimeline {
    public static List<String> runOrder = new List<String>();

    public class NsTimelineException extends Exception {
    }

    public class TaggedJob extends btcdev.QueueableJob {
        public String tag;
        public List<String> insertNext = new List<String>();

        public TaggedJob() {
        }

        public TaggedJob(String tag) {
            this.tag = tag;
        }

        public override void work() {
            NsTestJobTimeline.runOrder.add(tag);
            insert new Account(Name = 'NS-' + tag);
            for (String next : insertNext) {
                btcdev.Async.queueable(new TaggedJob(next)).name(next).nextInChain().enqueue();
            }
        }
    }

    public class LinkingJob extends btcdev.QueueableJob {
        public Id toLink;

        public override void work() {
            btcdev.Async.linkRecord(toLink);
        }
    }

    public class FailingJob extends btcdev.QueueableJob {
        public override void work() {
            throw new NsTimelineException('ns timeline failure');
        }
    }

    @IsTest
    static void shouldLinkRecordsAndNamesThroughTheNamespace() {
        Account linked = new Account(Name = 'NS-LINKED');
        insert linked;
        btcdev.AsyncMock.jobSettings(
            new List<btcdev__QueueableJobSetting__mdt>{
                new btcdev__QueueableJobSetting__mdt(
                    btcdev__QueueableJobName__c = 'All',
                    btcdev__TrackJobProgress__c = 'Yes'
                )
            }
        );

        Test.startTest();
        btcdev.Async.queueable(new TaggedJob('A'))
            .name('Reserve stock')
            .chainName('Order pipeline')
            .linkRecord(linked)
            .linkRecords(new Set<Id>{ linked.Id })
            .linkExternalRecord('NetSuite', 'Customer', '4711')
            .enqueue();
        Integer enqueuedRows = [
            SELECT COUNT()
            FROM btcdev__AsyncResult__c
            WHERE btcdev__Status__c = 'ENQUEUED'
        ];
        Test.stopTest();

        System.assertEquals(1, enqueuedRows, 'Tracking writes the row at enqueue.');
        btcdev__AsyncResult__c result = [
            SELECT btcdev__JobName__c, btcdev__ChainName__c, btcdev__Status__c, btcdev__StartedAt__c
            FROM btcdev__AsyncResult__c
        ];
        System.assertEquals('Reserve stock', result.btcdev__JobName__c);
        System.assertEquals('Order pipeline', result.btcdev__ChainName__c);
        System.assertEquals('COMPLETED', result.btcdev__Status__c);
        System.assertNotEquals(null, result.btcdev__StartedAt__c);
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM btcdev__AsyncResultLink__c
                WHERE btcdev__Key__c = :linked.Id
            ],
            'One link per record, even when given twice.'
        );
        btcdev__AsyncResultLink__c external = [
            SELECT btcdev__Source__c, btcdev__ObjectName__c
            FROM btcdev__AsyncResultLink__c
            WHERE btcdev__Key__c = '4711'
        ];
        System.assertEquals('NetSuite', external.btcdev__Source__c);
        System.assertEquals('Customer', external.btcdev__ObjectName__c);
    }

    @IsTest
    static void shouldLinkRecordsFromInsideWork() {
        Account linked = new Account(Name = 'NS-RUNTIME');
        insert linked;
        LinkingJob job = new LinkingJob();
        job.toLink = linked.Id;

        Test.startTest();
        btcdev.Async.queueable(job).enqueue();
        Test.stopTest();

        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM btcdev__AsyncResultLink__c
                WHERE btcdev__Key__c = :linked.Id
            ]
        );
    }

    @IsTest
    static void shouldRunNextInChainJobBeforeTheRestOfTheChain() {
        TaggedJob first = new TaggedJob('A');
        first.insertNext.add('X');

        Test.startTest();
        btcdev.Async.queueable(first).chain(new TaggedJob('B')).enqueue();
        Test.stopTest();

        System.assertEquals(new List<String>{ 'A', 'X', 'B' }, runOrder);
    }

    @IsTest
    static void shouldRequeueFailedAndSkippedTogetherWithTheDependencyRebuilt() {
        btcdev.AsyncMock.jobSettings(
            new List<btcdev__QueueableJobSetting__mdt>{
                new btcdev__QueueableJobSetting__mdt(
                    btcdev__QueueableJobName__c = 'All',
                    btcdev__CreateResult__c = true,
                    btcdev__StoreJobPayload__c = 'Yes',
                    btcdev__JobSerializerClass__c = 'NsJobSerializer'
                )
            }
        );
        Test.startTest();
        btcdev.Async.queueable(new FailingJob())
            .name('Blocker')
            .continueOnJobExecuteFail()
            .chain(new TaggedJob('B'))
            .name('Dependent')
            .dependsOn(btcdev.Async.afterPrevious().succeeded())
            .enqueue();
        Test.stopTest();

        Map<Id, btcdev__AsyncResult__c> stored = new Map<Id, btcdev__AsyncResult__c>(
            [
                SELECT Id, btcdev__Status__c, btcdev__ChainSequence__c, btcdev__CustomJobId__c
                FROM btcdev__AsyncResult__c
                WHERE btcdev__RequeueStatus__c = 'Stored'
            ]
        );
        System.assertEquals(2, stored.size(), 'Failed and skipped rows both carry a payload.');
        Set<String> originalCustomJobIds = new Set<String>();
        for (btcdev__AsyncResult__c row : stored.values()) {
            originalCustomJobIds.add(row.btcdev__CustomJobId__c);
        }

        btcdev.Async.RequeueSummary summary = btcdev.Async.requeue(stored.keySet());

        System.assertEquals(2, summary.requeued.size());
        System.assert(summary.droppedDependencyByResultId.isEmpty());
        List<btcdev.QueueableJob> replay = new List<btcdev.QueueableJob>();
        for (btcdev.QueueableJob job : summary.enqueueResult.queueableChainState.jobs) {
            if (!originalCustomJobIds.contains(job.customJobId)) {
                replay.add(job);
            }
        }
        System.assertEquals(2, replay.size(), 'Two replays wait in the chain.');
        System.assertEquals('Blocker', replay[0].jobName, 'Chain order is kept on replay.');
        System.assertEquals(
            replay[0].customJobId,
            replay[1].dependencies[0].resolvedTargetCustomJobId,
            'The dependency points at the replayed blocker.'
        );
    }
}
