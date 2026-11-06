public class RecordLinkJob extends btcdev.QueueableJob {
    public override void work() {
        btcdev.Async.linkRecords(new List<Id>());
        btcdev.Async.linkExternalRecords(new List<btcdev.Async.RecordLink>());
    }
}

Account linked = new Account(Name = 'NS-LINK-ANON');
insert linked;

btcdev.Async.Result chained = btcdev.Async.queueable(new RecordLinkJob())
    .name('Anon link')
    .chainName('Anon chain')
    .linkRecord(linked)
    .linkRecord(linked.Id)
    .linkRecords(new List<SObject>{ linked })
    .linkRecords(new List<Id>{ linked.Id })
    .linkRecords(new Set<Id>{ linked.Id })
    .linkExternalRecord('NetSuite', 'Customer', '4711')
    .linkExternalRecords(new List<btcdev.Async.RecordLink>{ new btcdev.Async.RecordLink('NetSuite', 'Customer', '4711') })
    .chain();
System.assertEquals('Anon link', chained.job.jobName);
System.assertEquals('Anon chain', chained.job.chainName);
System.assertEquals(2, chained.job.links.size(), 'Seven calls, one record and one external key, two links.');
System.assertEquals('Salesforce', chained.job.links[0].source);
System.assertEquals('Account', chained.job.links[0].objectName);
System.assertEquals('NetSuite', chained.job.links[1].source);
System.assertEquals('4711', chained.job.links[1].key);

btcdev.Async.queueable(new RecordLinkJob()).priority(1).chain();
try {
    btcdev.Async.queueable(new RecordLinkJob()).priority(1).nextInChain();
    System.assert(false, 'priority and nextInChain cannot combine');
} catch (Exception expected) {
    System.assert(expected.getMessage().contains('nextInChain'), expected.getMessage());
}

btcdev.Async.Result started = btcdev.Async.queueable().enqueue();
System.assertNotEquals(null, started.salesforceJobId);

btcdev.Async.RequeueSummary summary = new btcdev.Async.RequeueSummary();
System.assertNotEquals(null, summary.droppedDependencyByResultId);

System.debug('PASS: ns-test-record-link');
