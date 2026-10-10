---
outline: deep
---

# Batch Failures

## TL;DR

A batch scope that throws leaves almost nothing behind: a count on the Apex Jobs page and an
email. Add one interface to the batch and Async Lib records what failed, tells your logger, and
can run the failed records again.

```apex
public class AccountSyncBatch implements Database.Batchable<SObject>, Database.RaisesPlatformEvents {
    // start, execute, finish exactly as before
}
```

```apex
Async.requeueBatchFailures(
    new AccountSyncBatch(),
    failedBatchJobId,
    new List<SObjectField>{ Account.Name, Account.Industry }
);
```

This is for batches you have a reason to keep. For new work, read
[Batch or Chunk?](/explanations/batch-or-chunk) first.

## Turning it on

Two things, both opt-in.

1. **The batch implements `Database.RaisesPlatformEvents`.** It is a standard Salesforce marker
   interface with no methods. With it, the platform publishes a `BatchApexErrorEvent` for every
   transaction of the batch that ends in an unhandled exception. Async Lib ships the trigger that
   listens.
2. **`QueueableJobSetting__mdt` says what to do with it**, on the `All` record or on a record whose
   `QueueableJobName__c` is the batch class name:

| Field | Effect for a batch |
| ----- | ------------------ |
| `CreateResult__c` | write an `AsyncResult__c` row per failure. Needed for requeue |
| `LoggerClass__c` | call `onJobFailed` on that class per failure. Works without `CreateResult__c` |

It works for any batch in the org that has the interface, however it was started:
`Async.batchable(...)`, `Database.executeBatch`, a schedule, or the platform itself.

## What gets recorded

One `AsyncResult__c` row for each failed transaction. Three failed scopes are three rows.

| Field | Holds |
| ----- | ----- |
| `Status__c` | `FAILED` |
| `ClassName__c` | the batch class |
| `SalesforceJobId__c` | the id `Database.executeBatch` returned |
| `ExceptionType__c`, `ExceptionMessage__c` | what was thrown |
| `BatchPhase__c` | `START`, `EXECUTE` or `FINISH` |
| `BatchScope__c` | for `EXECUTE`, the ids of the records in the failed scope, comma-separated |
| `BatchScopeTruncated__c` | true when Salesforce cut that list short |
| `RequeueStatus__c` | blank while the failure is open, `Requeued` once it ran again |

Governor limit errors are included. `System.LimitException` cannot be caught in Apex, so this is
the only place a batch can report one.

Successful scopes write nothing. The platform only publishes failures.

::: info The job id is the one you already have
For a failed `execute`, the platform event names an internal worker job, not the batch job. Async
Lib resolves it, so `SalesforceJobId__c` always matches the id you got when you started the batch.
:::

## Logging

The class in `LoggerClass__c` is the same one that hears about Queueables. A batch failure arrives
on `Async.OnJobFailed`:

```apex
global class AsyncJobLogger implements Async.OnJobFailed {
    public void onJobFailed(Async.FailureContext ctx) {
        if (ctx.asyncType == Async.AsyncType.BATCHABLE) {
            Logger.error(ctx.className + ' failed in ' + ctx.batchPhase + ': ' + ctx.failure.message);
            return;
        }
        Logger.error(ctx.className + ' failed: ' + ctx.failure.message);
    }
}
```

| `FailureContext` field | For a batch failure |
| ---------------------- | ------------------- |
| `asyncType` | `BATCHABLE` |
| `salesforceJobId` | the batch job id |
| `className`, `failure.type`, `failure.message` | as recorded |
| `batchPhase`, `batchScope`, `batchScopeTruncated` | as recorded |
| `retryOutcome` | always `NOT_CONFIGURED` |
| `customJobId`, `retryHistory`, `info` | empty. They belong to Queueables |

::: warning The logger runs as the Automated Process user
A platform event trigger does not run as the person who started the batch. Your logger sees
`UserInfo.getUserId()` as Automated Process for a batch failure, and anything it enqueues runs as
that user too. Log, do not launch work from there.
:::

A logger that throws does not lose the record. The row is written first.

## Running the failed records again

```apex
Async.RequeueSummary summary = Async.requeueBatchFailures(
    new AccountSyncBatch(),
    failedBatchJobId,
    new List<SObjectField>{ Account.Name, Account.Industry }
);

summary.requeued;              // the failure rows that will run again
summary.skipReasonByResultId;  // the rest, and why
summary.enqueueResult;         // the batch job doing the requeue
```

It starts a batch that walks the open failure rows of that job. For each one it reloads the failed
records, hands them to **your batch's own `execute()`**, and marks the row `Requeued`. The logic is
not copied anywhere, and it runs as a batch, with batch limits, at the scope size the original run
used.

### Saying what to reload

A failure stores record ids, not records. Your `execute()` reads fields, so the requeue has to
know which ones. There is no version of the call that leaves this out.

**A field list.** Async Lib builds the query itself, selecting `Id` and your fields from the
failed records and nothing else, so it cannot load the wrong rows. The object comes from the ids.

```apex
Async.requeueBatchFailures(batch, jobId, new List<SObjectField>{ Account.Name });
```

**Field paths as strings**, when `execute()` reads a parent field:

```apex
Async.requeueBatchFailures(batch, jobId, new List<String>{ 'Name', 'Owner.Email' });
```

Only plain field paths are accepted, and the query is validated before anything is started. A typo
fails in your transaction, not in a batch an hour later.

**A loader**, for anything a field list cannot say:

```apex
public class AccountLoader implements Async.BatchRecordLoader {
    public List<SObject> load(Set<Id> failedRecordIds) {
        return [
            SELECT Id, Name, (SELECT Id FROM Contacts)
            FROM Account
            WHERE Id IN :failedRecordIds
        ];
    }
}

Async.requeueBatchFailures(batch, jobId, new AccountLoader());
```

The loader has to be a class saved in the org. It travels inside the requeue batch, and a class
declared in an anonymous Apex script stops existing when the script ends. The call rejects such a
loader up front. From anonymous Apex, use a field list, or save the loader first.

A batch whose `execute()` reads nothing but `Id`, because it re-queries inside, passes an empty
list: `new List<SObjectField>()`. Passing `null` is rejected, so "I forgot" and "I need nothing"
never look the same.

The two field-list forms reload in system mode and without sharing, so every failed record comes
back whoever starts the requeue. Use a loader if you need something else.

### What keeps it safe

- **A scope that fails again stays open.** The row is marked in the same transaction that runs the
  scope. If `execute()` throws, the mark rolls back with everything else, and you can requeue it
  again after the next fix.
- **Two requeues at once do not double the work.** Each scope locks its row first and skips it if
  another run already took it.
- **The wrong batch is refused.** The class you pass has to be the class that failed.
- **Everything is checked before a batch starts**: the batch instance, the job id, the reload, the
  field paths.
- **"Nothing to requeue" is never a guess.** A job that had no failures returns an empty summary.
  A job id that matches no batch job throws. So does a job that reports failed scopes when you can
  see no failure record for it: either the failures were not recorded, or you have no access to
  `AsyncResult__c` records. The message names both.

`execute()` still has to be safe to run again on the same records. That is true of any retry.

### What it cannot do

| | |
| --- | --- |
| A failure in `START` or `FINISH` | has no records, so it is listed in `skipReasonByResultId` |
| A scope with `BatchScopeTruncated__c` | is skipped. Running part of it would silently drop records |
| `finish()` | is not called by a requeue |
| `Database.Stateful` totals | start fresh. The original run's state is gone |
| A batch without `CreateResult__c` | has no rows, so the call throws and says so |
| Automatic retry | does not exist for batches. See [Batch or Chunk?](/explanations/batch-or-chunk) |

The requeue runs as the user who calls it, and with sharing. The failed records themselves are
always reloaded. Queries your `execute()` runs on its own follow that user's access, unless the
batch class says `without sharing`.

Call it from a user context: a button, a scheduled class, anonymous Apex. Do not call it from the
batch's own `finish()`. The last failure of a run is delivered about a second after `finish()`
starts, so it would be missed.

If you put it behind a button, gate the button. It runs a batch over records the caller may not
be able to see, the same concern as
[`Async.requeue`](/explanations/requeue#if-you-put-this-behind-a-button-gate-the-button).

`Async.requeue(resultId)` does not accept a batch failure row. It replays a stored Queueable
payload, and a batch failure has none. The skip reason points here.

## Testing

`Test.stopTest()` rethrows the batch's exception, and the platform event is only delivered when
you ask:

```apex
@IsTest
static void recordsTheFailedScope() {
    AsyncMock.jobSettings(
        new List<QueueableJobSetting__mdt>{
            new QueueableJobSetting__mdt(QueueableJobName__c = 'All', CreateResult__c = true)
        }
    );

    try {
        Test.startTest();
        Async.batchable(new AccountSyncBatch()).execute();
        Test.stopTest();
    } catch (Exception thrownByTheBatch) {
        // expected: this is the failure under test
    }
    Test.getEventBus().deliver();

    Assert.areEqual(1, [SELECT COUNT() FROM AsyncResult__c WHERE BatchPhase__c = 'EXECUTE']);
}
```

## On a packaged install

Nothing extra. The batch stays `public`, because you hand Async Lib an instance and it never looks
the class up by name. The same goes for a `BatchRecordLoader`. Only the logger is `global`, as it
already is for Queueables. Prefix as usual: `btcdev.Async.requeueBatchFailures(...)`,
`btcdev.Async.BatchRecordLoader`, `btcdev__BatchScope__c`.
