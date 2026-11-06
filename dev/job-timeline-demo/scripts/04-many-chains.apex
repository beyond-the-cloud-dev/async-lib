if (![SELECT Id FROM AsyncResult__c WHERE ChainId__c = 'fabrikam-1' LIMIT 1].isEmpty()) {
    return;
}
List<Account> existing = [SELECT Id FROM Account WHERE Name = 'Fabrikam Order #20001' LIMIT 1];
Account order = existing.isEmpty() ? new Account(Name = 'Fabrikam Order #20001') : existing[0];
upsert order;
List<AsyncResult__c> rows = new List<AsyncResult__c>();
for (Integer chain = 1; chain <= 80; chain++) {
    Boolean fails = Math.mod(chain, 5) == 0;
    for (Integer step = 1; step <= 12; step++) {
        Boolean failedStep = fails && step == 12;
        rows.add(
            new AsyncResult__c(
                ChainId__c = 'fabrikam-' + chain,
                ChainName__c = 'Fabrikam sync ' + chain,
                ChainSequence__c = step,
                CustomJobId__c = 'fabrikam-' + chain + '-' + step,
                JobName__c = 'Step ' + step,
                ClassName__c = 'TimelineDemoJobs.StepJob',
                Status__c = failedStep ? 'FAILED' : 'COMPLETED',
                ExceptionType__c = failedStep ? 'TimelineDemoJobs.DemoException' : null,
                ExceptionMessage__c = failedStep ? 'Seeded failure on the last step' : null,
                StartedAt__c = System.now().addMinutes(-chain),
                FinishedAt__c = System.now().addMinutes(-chain).addSeconds(step)
            )
        );
    }
}
insert rows;
List<AsyncResultLink__c> links = new List<AsyncResultLink__c>();
for (AsyncResult__c row : rows) {
    links.add(
        new AsyncResultLink__c(
            AsyncResult__c = row.Id,
            Key__c = order.Id,
            Source__c = 'Salesforce',
            ObjectName__c = 'Account'
        )
    );
}
insert links;
System.debug('SEEDED MANY CHAINS');
