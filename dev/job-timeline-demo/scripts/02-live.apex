Account order = [SELECT Id FROM Account WHERE Name = 'Northwind Order #10248' ORDER BY CreatedDate DESC LIMIT 1];
Account other = [SELECT Id FROM Account WHERE Name = 'Contoso Order #10301' ORDER BY CreatedDate DESC LIMIT 1];

QueueableBuilder live = Async.queueable(new TimelineDemoJobs.StepJob(1))
    .name('Validate order').chainName('Live demo pipeline').linkRecord(order);
for (Integer i = 2; i <= 10; i++) {
    QueueableJob step;
    if (i == 4) {
        step = new TimelineDemoJobs.LinkingJob(other.Id);
    } else if (i == 7) {
        step = new TimelineDemoJobs.FlakyJob(1);
    } else if (i == 9) {
        step = new TimelineDemoJobs.FailingJob('Payment gateway returned 502 Bad Gateway');
    } else {
        TimelineDemoJobs.StepJob slow = new TimelineDemoJobs.StepJob(i);
        slow.spinMs = 4000;
        step = slow;
    }
    live = live.chain(step).name('Live step ' + i).linkRecord(order);
    if (i == 7) {
        live = live.retry(1).backoff(Async.Backoff.fixed(1));
    }
    if (i == 9) {
        live = live.retry(1).backoff(Async.Backoff.fixed(1)).continueOnJobExecuteFail();
    }
    if (i == 10) {
        live = live.dependsOn(Async.afterPrevious().succeeded());
    }
}
live.enqueue();
System.debug('LIVE SEEDED');
