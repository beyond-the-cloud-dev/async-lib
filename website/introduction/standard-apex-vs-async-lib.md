---
outline: deep
---

# Standard Apex vs Async Lib

If you already know how to write a `Queueable`, a `Database.Batchable`, or a
`Schedulable` in plain Apex, this page maps each of those to its Async Lib
equivalent. Same concepts, less boilerplate, no "Too many queueable jobs"
errors.

Async Lib only wraps the **enqueue, chain, and schedule** parts. Your business
logic stays where it always was, so things like `Database.Stateful`,
`QueryLocator`, and finalizer context work exactly the same.

## At a glance

| Standard Apex                                  | Async Lib                                                  |
| ---------------------------------------------- | --------------------------------------------------------- |
| `implements Queueable` + `execute(context)`    | `extends QueueableJob` + `work()`                         |
| `System.enqueueJob(job)`                        | `Async.queueable(job).enqueue()`                          |
| Enqueue next job inside `execute()`            | `.chain(new NextJob())`                                   |
| 1 child queueable per transaction (hard limit) | Automatic overflow to a scheduled batch, no limit         |
| `System.attachFinalizer` + `implements Finalizer` | `extends QueueableJob.Finalizer` + `attachFinalizer()` |
| `Database.executeBatch(job, scope)`            | `Async.batchable(job).scopeSize(scope).execute()`         |
| `implements Schedulable` + `System.schedule`   | `Async.schedulable(job).cronExpression(...).schedule()`   |
| Hand-written cron string                       | `CronBuilder` fluent helpers                              |

## Queueable

### Defining a job

In standard Apex you `implements Queueable` and put your logic in
`execute(QueueableContext)`. With Async Lib you `extends QueueableJob` and
override `work()`. The Salesforce `QueueableContext` is still available through
the job context.

**Standard Apex**

```apex
public class AccountProcessorJob implements Queueable {
  private List<Id> accountIds;

  public AccountProcessorJob(List<Id> accountIds) {
    this.accountIds = accountIds;
  }

  public void execute(QueueableContext context) {
    List<Account> accounts = [SELECT Id, Name FROM Account WHERE Id IN :accountIds];
    // ... process accounts ...
    update accounts;
  }
}
```

**Async Lib**

```apex
public class AccountProcessorJob extends QueueableJob {
  private List<Id> accountIds;

  public AccountProcessorJob(List<Id> accountIds) {
    this.accountIds = accountIds;
  }

  public override void work() {
    QueueableContext context = Async.getQueueableJobContext().queueableCtx;
    List<Account> accounts = [SELECT Id, Name FROM Account WHERE Id IN :accountIds];
    // ... process accounts ...
    update accounts;
  }
}
```

### Enqueuing

**Standard Apex**

```apex
System.enqueueJob(new AccountProcessorJob(accountIds));
```

**Async Lib**

```apex
Async.queueable(new AccountProcessorJob(accountIds))
    .priority(5)
    .enqueue();
```

The builder adds options you'd otherwise hand-roll: `priority`, `delay`,
`retry`, rollback/continue-on-failure, and more. See the
[Queueable API](/api/queueable) for the full list.

### Chaining jobs

Standard Apex lets you enqueue **one** child queueable from inside a running
queueable. Go past that and you hit `System.AsyncException: Too many queueable
jobs added to the queue: 2`. Async Lib chains as many jobs as you want and
automatically overflows to a scheduled batch when the platform limit is reached.

**Standard Apex**

```apex
public class FirstJob implements Queueable {
  public void execute(QueueableContext context) {
    // ... work ...
    System.enqueueJob(new SecondJob()); // only one allowed per transaction
  }
}
```

**Async Lib**

```apex
Async.queueable(new FirstJob())
    .chain(new SecondJob())
    .chain(new ThirdJob())
    .enqueue();
```

Async Lib also adds [`dependsOn(...)`](/api/queueable#dependson) so a chained job
can run only when an earlier one succeeded, failed, or finished. There is no
standard-Apex equivalent.

### Finalizers

A finalizer runs after the job completes, whether it succeeded or threw. The
shape is the same in both worlds; Async Lib just attaches it through the builder
and exposes the `FinalizerContext` through the job context.

**Standard Apex**

```apex
public class CleanupFinalizer implements Finalizer {
  public void execute(FinalizerContext context) {
    if (context.getResult() == ParentJobResult.SUCCESS) {
      System.debug('Job succeeded');
    } else {
      System.debug('Job failed: ' + context.getException().getMessage());
    }
  }
}

public class MainJob implements Queueable {
  public void execute(QueueableContext context) {
    System.attachFinalizer(new CleanupFinalizer());
    // ... work ...
  }
}
```

**Async Lib**

```apex
public class CleanupFinalizer extends QueueableJob.Finalizer {
  public override void work() {
    FinalizerContext context = Async.getQueueableJobContext().finalizerCtx;
    if (context.getResult() == ParentJobResult.SUCCESS) {
      System.debug('Job succeeded');
    } else {
      System.debug('Job failed: ' + context.getException().getMessage());
    }
  }
}

public class MainJob extends QueueableJob {
  public override void work() {
    Async.queueable(new CleanupFinalizer()).attachFinalizer();
    // ... work ...
  }
}
```

## Batchable

Your batch class does **not** change. It is a normal
`Database.Batchable<SObject>` with `start()`, `execute()`, and `finish()`. Async
Lib only replaces the `Database.executeBatch(...)` call, adding scheduling and
result tracking on top.

**Standard Apex**

```apex
Database.executeBatch(new AccountCleanupBatch(), 200);
```

**Async Lib**

```apex
Async.batchable(new AccountCleanupBatch())
    .scopeSize(200)
    .execute();
```

### Does `Database.Stateful` work the same?

Yes. State is kept on **your** batch class, which Async Lib never touches.
Implement `Database.Stateful` exactly as you do today.

```apex
public class AccountCleanupBatch implements Database.Batchable<SObject>, Database.Stateful {
  public Integer deletedCount = 0;

  public Database.QueryLocator start(Database.BatchableContext bc) {
    return Database.getQueryLocator('SELECT Id FROM Account WHERE Is_Active__c = false');
  }

  public void execute(Database.BatchableContext bc, List<Account> scope) {
    delete scope;
    deletedCount += scope.size(); // preserved across batches by Database.Stateful
  }

  public void finish(Database.BatchableContext bc) {
    System.debug('Deleted ' + deletedCount + ' accounts');
  }
}
```

### How do I use `QueryLocator`?

The same way. Return it from `start()` as usual (see the example above). Async
Lib hands your job straight to `Database.executeBatch`, so the query locator,
chunking, and 50-million-row limit all behave identically.

### Should I move my logic into `work()`?

No. `work()` belongs to **queueable** jobs (`QueueableJob`). A batch keeps its
`start()` / `execute()` / `finish()` methods. The only thing that moves is how
you kick it off: `Async.batchable(job).execute()` instead of
`Database.executeBatch(job)`.

## Schedulable

Your `Schedulable` class is unchanged. Async Lib wraps `System.schedule`, builds
the cron expression for you, and can skip scheduling when a job of the same name
already exists (so you don't have to catch the "already scheduled" exception).

**Standard Apex**

```apex
public class NightlyJob implements Schedulable {
  public void execute(SchedulableContext context) {
    // ... work ...
  }
}

// daily at 02:00 — cron string written by hand
System.schedule('Nightly Job', '0 0 2 * * ? *', new NightlyJob());
```

**Async Lib**

```apex
Async.schedulable(new NightlyJob())
    .name('Nightly Job')
    .cronExpression('0 0 2 * * ? *')
    .skipWhenAlreadyScheduled()
    .schedule();
```

### Building the cron expression

Instead of remembering cron field order, use `CronBuilder`.

**Standard Apex**

```apex
// every day at 02:00
System.schedule('Nightly Job', '0 0 2 * * ? *', new NightlyJob());
```

**Async Lib**

```apex
Async.schedulable(new NightlyJob())
    .name('Nightly Job')
    .cronExpression(new CronBuilder().everyDay(2, 0))
    .schedule();
```

See the [Schedulable API](/api/schedulable#build---cron-expression) for the full
set of `CronBuilder` helpers (`everyHour`, `everyXHours`, `everyMonth`, and so
on).

### Scheduling a queueable or batch

Standard Apex has no direct way to schedule a queueable. With Async Lib, any
queueable or batch builder converts to a schedulable with `asSchedulable()`.

```apex
Async.queueable(new AccountProcessorJob(accountIds))
    .asSchedulable()
    .name('Hourly Account Processing')
    .cronExpression(new CronBuilder().everyHour(0))
    .schedule();
```
