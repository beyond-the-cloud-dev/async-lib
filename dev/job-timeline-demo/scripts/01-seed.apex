List<Account> orders = [SELECT Id FROM Account WHERE Name = 'Northwind Order #10248' ORDER BY CreatedDate DESC LIMIT 1];
List<Account> others = [SELECT Id FROM Account WHERE Name = 'Contoso Order #10301' ORDER BY CreatedDate DESC LIMIT 1];
Boolean firstSeed = orders.isEmpty();
Account order = firstSeed ? new Account(Name = 'Northwind Order #10248') : orders[0];
Account other = others.isEmpty() ? new Account(Name = 'Contoso Order #10301') : others[0];
List<Account> newAccounts = new List<Account>();
if (order.Id == null) newAccounts.add(order);
if (other.Id == null) newAccounts.add(other);
insert newAccounts;
List<Contact> contacts = [SELECT Id FROM Contact WHERE AccountId = :order.Id];
List<Opportunity> opps = [SELECT Id FROM Opportunity WHERE AccountId = :order.Id];
if (firstSeed) {
    contacts = new List<Contact>{
        new Contact(LastName = 'Fuller', FirstName = 'Andrew', AccountId = order.Id),
        new Contact(LastName = 'Leverling', FirstName = 'Janet', AccountId = order.Id),
        new Contact(LastName = 'Peacock', FirstName = 'Margaret', AccountId = order.Id)
    };
    insert contacts;
    opps = new List<Opportunity>{
        new Opportunity(Name = 'Northwind renewal', AccountId = order.Id, StageName = 'Prospecting', CloseDate = Date.today().addDays(30)),
        new Opportunity(Name = 'Northwind upsell', AccountId = order.Id, StageName = 'Prospecting', CloseDate = Date.today().addDays(60))
    };
    insert opps;
}
List<Account> lines = [SELECT Id FROM Account WHERE Name LIKE 'Line %' ORDER BY CreatedDate, Name LIMIT 600];
if (lines.size() < 600) {
    List<Account> missingLines = new List<Account>();
    for (Integer i = lines.size(); i < 600; i++) {
        missingLines.add(new Account(Name = 'Line ' + i));
    }
    insert missingLines;
    lines.addAll(missingLines);
}
List<Account> firstLines = new List<Account>();
for (Integer i = 0; i < 25; i++) {
    firstLines.add(lines[i]);
}

Async.Result reserve = Async.queueable(new TimelineDemoJobs.StepJob(1))
    .name('Reserve stock').chainName('Order fulfilment pipeline')
    .linkRecord(order).linkRecords(new List<Account>{ lines[0], lines[1], lines[2], lines[3], lines[4] })
    .chain();
Async.queueable(new TimelineDemoJobs.StepJob(2)).name('Create invoice').linkRecord(order).priority(1).chain();
Async.Result commission = Async.queueable(new TimelineDemoJobs.FailingJob(
        'UNABLE_TO_LOCK_ROW: record 001XX000003GXYZ is currently being modified by another user. ' +
        'The commission split could not be written and was rolled back.'))
    .name('Commission split').linkRecord(order)
    .retry(2).backoff(Async.Backoff.fixed(1)).continueOnJobExecuteFail()
    .chain();
Async.Result rollups = Async.queueable(new TimelineDemoJobs.StepJob(4)).name('Recalculate account rollups').linkRecord(order)
    .dependsOn(Async.after(commission).succeeded()).chain();
Async.queueable(new TimelineDemoJobs.StepJob(5)).name('Sync to ERP').linkRecord(order)
    .dependsOn(Async.after(rollups).succeeded()).chain();
Async.queueable(new TimelineDemoJobs.StepJob(6)).name('Open support case').linkRecord(order)
    .dependsOn(Async.after(commission).failed()).chain();
Async.queueable(new TimelineDemoJobs.StepJob(7)).name('Archive order').linkRecord(order)
    .dependsOn(Async.after(reserve).succeeded()).chain();
Async.queueable(new TimelineDemoJobs.StepJob(8)).name('Notify sales team').linkRecord(order).chain();
Async.queueable().enqueue();

QueueableBuilder longChain = Async.queueable(new TimelineDemoJobs.StepJob(1))
    .name('Step 1').chainName('Nightly price refresh (60 steps)').linkRecord(order);
for (Integer i = 2; i <= 60; i++) {
    QueueableJob step = new TimelineDemoJobs.StepJob(i);
    if (i == 10) {
        step = new TimelineDemoJobs.FlakyJob(1);
    } else if (i == 30) {
        step = new TimelineDemoJobs.LinkingJob(other.Id);
    }
    longChain = longChain.chain(step).name('Step ' + i).linkRecord(order);
    if (i == 10) {
        longChain = longChain.retry(1).backoff(Async.Backoff.fixed(1));
    }
}
longChain.enqueue();

Async.chunk(new TimelineDemoJobs.PageJob(), ChunkSource.of(lines)).chunkSize(2)
    .name('Reprice lines').chainName('Reprice 600 lines').linkRecord(order).enqueue();

Async.chunk(new TimelineDemoJobs.FragilePageJob(), ChunkSource.of(firstLines)).chunkSize(3)
    .stopRemainingChunksOnFailure()
    .name('Validate lines').chainName('Validate 25 lines').linkRecord(order).enqueue();

Async.queueable(new TimelineDemoJobs.StepJob(1)).name('Close periods').chainName('Month-end close').linkRecord(order)
    .chain(new TimelineDemoJobs.StopChainJob()).name('Check ledger balance').linkRecord(order)
    .chain(new TimelineDemoJobs.StepJob(3)).name('Post journals').linkRecord(order)
    .chain(new TimelineDemoJobs.StepJob(4)).name('Lock books').linkRecord(order)
    .enqueue();

Async.Result plan = Async.queueable(new TimelineDemoJobs.SkipperJob()).name('Plan hygiene run').chainName('Data hygiene').linkRecord(order).chain();
Async.queueable(new TimelineDemoJobs.StepJob(2)).name('Dedupe contacts').linkRecord(order).chain();
Async.Result purge = Async.queueable(new TimelineDemoJobs.StepJob(3)).name('Purge stale leads').linkRecord(order).chain();
Async.queueable(new TimelineDemoJobs.StepJob(4)).name('Hygiene report').linkRecord(order).chain();
((TimelineDemoJobs.SkipperJob) plan.job).targetCustomJobId = purge.job.customJobId;
Async.queueable().enqueue();

List<Id> many = new List<Id>{ order.Id };
for (Contact c : contacts) { many.add(c.Id); }
for (Opportunity o : opps) { many.add(o.Id); }
for (Account line : firstLines) { many.add(line.Id); }
Async.queueable(new TimelineDemoJobs.RelatedLinkingJob(order.Id))
    .name('Account 360 refresh').chainName('Account 360').linkRecords(many).enqueue();

Async.queueable(new TimelineDemoJobs.StepJob(1)).linkRecord(order)
    .chain(new TimelineDemoJobs.StepJob(2)).linkRecord(order).enqueue();

Async.queueable(new TimelineDemoJobs.StepJob(1)).name('Export orders').chainName('Delayed export')
    .linkRecord(order).delay(5)
    .chain(new TimelineDemoJobs.StepJob(2)).name('Upload to SFTP').linkRecord(order)
    .enqueue();

for (Integer c = 1; c <= 12; c++) {
    Async.queueable(new TimelineDemoJobs.StepJob(1)).name('Load price book').chainName('Price check ' + c).linkRecord(order)
        .chain(new TimelineDemoJobs.StepJob(2)).name('Compare').linkRecord(order)
        .chain(new TimelineDemoJobs.StepJob(3)).name('Report').linkRecord(order)
        .enqueue();
}
System.debug('SEEDED ' + order.Id);

List<Account> twentyLines = new List<Account>();
for (Integer i = 0; i < 20; i++) { twentyLines.add(lines[i]); }
List<Account> twelveLines = new List<Account>();
for (Integer i = 20; i < 32; i++) { twelveLines.add(lines[i]); }
TimelineDemoJobs.StepJob mixedPrepare = new TimelineDemoJobs.StepJob(1);
mixedPrepare.spinMs = 3000;
TimelineDemoJobs.StepJob mixedReconcile = new TimelineDemoJobs.StepJob(2);
mixedReconcile.spinMs = 3000;
TimelineDemoJobs.StepJob mixedPublish = new TimelineDemoJobs.StepJob(3);
mixedPublish.spinMs = 3000;
Async.queueable(mixedPrepare).name('Prepare order').chainName('Order sync (mixed)').linkRecord(order)
    .chunk(new TimelineDemoJobs.PageJob(), ChunkSource.of(twentyLines)).chunkSize(2)
        .name('Reprice 20 lines').linkRecord(order)
    .chain(mixedReconcile).name('Reconcile totals').linkRecord(order)
    .chunk(new TimelineDemoJobs.PageJob(), ChunkSource.of(twelveLines)).chunkSize(2)
        .name('Tax 12 lines').linkRecord(order)
    .chain(mixedPublish).name('Publish order').linkRecord(order)
    .chain(new TimelineDemoJobs.StepJob(4)).name('Notify owner').linkRecord(order)
    .enqueue();
