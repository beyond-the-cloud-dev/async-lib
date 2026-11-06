public class ResultTrackJob extends btcdev.QueueableJob {
    public override void work() {
    }
}

List<btcdev__QueueableJobSetting__mdt> settings = [
    SELECT btcdev__QueueableJobName__c, btcdev__IsDisabled__c, btcdev__CreateResult__c
    FROM btcdev__QueueableJobSetting__mdt
    LIMIT 10
];
System.assertNotEquals(null, settings);

Boolean hasAllSetting = false;
for (btcdev__QueueableJobSetting__mdt s : settings) {
    if (s.btcdev__QueueableJobName__c == 'All') {
        hasAllSetting = true;
    }
}
System.assert(hasAllSetting, 'Should have the global "All" QueueableJobSetting record');

btcdev.Async.Result ar = btcdev.Async.queueable(new ResultTrackJob()).enqueue();
System.assertNotEquals(null, ar);
System.assertNotEquals(null, ar.customJobId);
System.assertNotEquals(null, ar.salesforceJobId);
System.assertEquals(btcdev.Async.AsyncType.QUEUEABLE, ar.asyncType);

System.debug('PASS: ns-test-result-tracking');
