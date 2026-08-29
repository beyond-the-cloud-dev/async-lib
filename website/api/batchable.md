# Batchable API

Apex classes `BatchableBuilder.cls` and `BatchableManager.cls`.

New to async jobs? See
[Standard Apex vs Async Lib](/introduction/standard-apex-vs-async-lib#batchable)
for how this maps to a plain `Database.executeBatch`.

**Common BatchJob class example:**

Your batch class is a normal `Database.Batchable`. Async Lib does not change it,
so `Database.Stateful`, `Database.QueryLocator`, and the `start` / `execute` /
`finish` methods all work as usual.

```apex
public class AccountCleanupBatch implements Database.Batchable<SObject>, Database.Stateful {
  public Integer deletedCount = 0;

  public Database.QueryLocator start(Database.BatchableContext bc) {
    return Database.getQueryLocator('SELECT Id FROM Account WHERE IsActive__c = false');
  }

  public void execute(Database.BatchableContext bc, List<Account> scope) {
    delete scope;
    deletedCount += scope.size();
  }

  public void finish(Database.BatchableContext bc) {
    System.debug('Deleted ' + deletedCount + ' accounts');
  }
}
```

**Common Batchable example:**

```apex
Async.Result result = Async.batchable(new AccountCleanupBatch())
	.scopeSize(100)
	.execute();

System.debug('Batch job enqueued: ' + result.salesforceJobId);
```

::: tip Ready-made cleanup batch

Async Lib ships `AsyncResultCleanupBatch` for deleting old `AsyncResult__c`
records, with separate retention for failed results and the rest. See
[AsyncResult Cleanup](/explanations/asyncresult-cleanup).

:::

## Methods

The following are methods for using Async with Batchable jobs:

[**INIT**](#init)

- [`batchable(Database.Batchable<Object> job)`](#batchable)

[**Build**](#build)

- [`scopeSize(Integer size)`](#scopesize)
- [`minutesFromNow(Integer minutes)`](#minutesfromnow)
- [`asSchedulable()`](#asschedulable)

[**Execute**](#execute)

- [`execute()`](#execute-1)

### INIT

#### batchable

Constructs a new BatchableBuilder instance with the specified batchable job.

**Signature**

```apex
Async batchable(Database.Batchable<Object> job);
```

**Example**

```apex
Async.batchable(new MyBatchJob());
```

### Build

#### scopeSize

Allows setting the scope size for the batch job.

**Signature**

```apex
BatchableBuilder scopeSize(Integer size);
```

**Example**

```apex
Async.batchable(new MyBatchJob())
	.scopeSize(100);
```

#### minutesFromNow

Allows scheduling the batch job to run after a specified number of minutes.

**Signature**

```apex
BatchableBuilder minutesFromNow(Integer minutes);
```

**Example**

```apex
Async.batchable(new MyBatchJob())
	.minutesFromNow(10);
```

#### asSchedulable

Converts the batch builder to a schedulable builder for cron-based scheduling.
See [Schedulable API](/api/schedulable) for scheduling options.

**Signature**

```apex
SchedulableBuilder asSchedulable();
```

**Example**

```apex
Async.batchable(new MyBatchJob())
	.asSchedulable();
```

### Execute

#### execute

Executes the batch job with the configured options. Returns an Async.Result.

**Signature**

```apex
Async.Result execute();
```

**Example**

```apex
Async.Result result = Async.batchable(new MyBatchJob())
	.scopeSize(100)
	.execute();
```

Returns `result.salesforceJobId` containing the Salesforce Job Id.
