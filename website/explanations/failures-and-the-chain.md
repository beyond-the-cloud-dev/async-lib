---
outline: deep
---

# What a Failed Job Does to the Chain

## TL;DR

Two different things happen when a job fails, and they are easy to confuse:

- **Jobs that were already in the chain keep running.** A failure does not stop
  the chain. Use [`dependsOn(...)`](/api/queueable#dependson) to gate them.
- **Jobs the failing job created during `work()` do not run**, unless its
  transaction committed. Same for a
  [`stopChain()`](/api/queueable#stopchain) or
  [`skipJob(...)`](/api/queueable#skipjob) it called.

The rule for the second one: **if the attempt's transaction did not commit,
nothing that attempt did to the chain happened.** That matches plain Apex, where
a `System.enqueueJob()` inside a Queueable that throws is rolled back and the
child job never runs.

## Why this needs explaining

In plain Apex the answer is simple, because the platform gives it to you:

```apex
public class ParentJob implements Queueable {
    public void execute(QueueableContext ctx) {
        insert new Account(Name = 'Parent');
        System.enqueueJob(new ChildJob());
        throw new CalloutException('boom');
    }
}
```

The exception aborts the transaction. The Account is rolled back and so is the
enqueue, so `ChildJob` never runs.

Async Lib does not call `System.enqueueJob` for you there. Inside a running job,
`.chain()` and `.enqueue()` both just add to the chain **in memory**, and the
chain travels to the next transaction inside the finalizer. A rollback does not
touch it, because there is nothing in the database to roll back.

So Async Lib has to reproduce that rollback itself, which is what it now does.

## What counts as "did not commit"

Two separate things ride on this, so the table splits them:

| Situation | Transaction committed | Jobs it chained inside `work()` | Its `stopChain()` / `skipJob()` |
| --- | --- | --- | --- |
| Job succeeds | yes | run | stands |
| `work()` throws, default flags | no, the platform rolled it back | discarded | undone |
| [`rollbackOnJobExecuteFail()`](/api/queueable#rollbackonjobexecutefail) | no, the DML went back to a savepoint | discarded | undone |
| [`continueOnJobExecuteFail()`](/api/queueable#continueonjobexecutefail) | yes, the partial DML is committed | run | stands |
| Uncatchable failure (governor `LimitException`) | no | discarded | undone |
| Attempt that will be [retried](/api/queueable#retry) | not relevant, the attempt is thrown away | discarded | undone |

The last two rows are the ones people get wrong.

An uncatchable failure never reaches a `catch`, so
`continueOnJobExecuteFail()` does not run and the transaction dies anyway. The
framework reads the outcome from the finalizer, not from your flags, so this is
handled correctly.

A retried attempt is discarded whether or not it committed. `work()` re-runs on
the next attempt and will chain the same jobs again, so keeping the first
attempt's would double them.

## Worked example

```apex
public class ImportJob extends QueueableJob {
    public override void work() {
        insert new ImportBatch__c(Status__c = 'Running');
        Async.queueable(new NotifyJob()).chain();
        callTheApiThatIsDown();
    }
}
```

```apex
Async.queueable(new ImportJob()).chain(new CleanupJob()).enqueue();
```

`callTheApiThatIsDown()` throws.

- `ImportBatch__c` is rolled back by the platform.
- `NotifyJob` does **not** run. `ImportJob` created it during the attempt that
  died, so it goes with it.
- `CleanupJob` **does** run. It was in the chain before `ImportJob` started, so
  it is not `ImportJob`'s to cancel.

Add `.continueOnJobExecuteFail()` to `ImportJob` and both the `ImportBatch__c`
row and `NotifyJob` survive, because now the transaction commits.

## Attached finalizers always survive

[`attachFinalizer()`](/api/queueable#attachfinalizer) is the exception, and it
mirrors the platform: `System.attachFinalizer` survives an unhandled exception,
`System.enqueueJob` does not.

```apex
public class ImportJob extends QueueableJob {
    public override void work() {
        Async.queueable(new AlertOpsFinalizer()).attachFinalizer();
        callTheApiThatIsDown();
    }
}
```

`AlertOpsFinalizer` runs. Reacting to the failure is the whole point of a
finalizer, so it would be useless if the failure discarded it.

## Stopping the chain on purpose

`Async.stopChain()` and `Async.skipJob(...)` follow the same rule as chaining.
Called from an attempt that then dies, they are undone.

That matters most with retries. Without the rule, a `stopChain()` from attempt 1
would survive into attempt 2 even though the framework threw attempt 1 away, so
a job that eventually **succeeded** would still have killed everything behind it.

If you want a stop to stick even though the job failed, make the job's
transaction commit. Catch the exception yourself:

```apex
public override void work() {
    try {
        riskyThing();
    } catch (Exception ex) {
        Async.stopChain();
    }
}
```

Or stop from a finalizer, which runs in its own transaction:

```apex
public class GuardFinalizer extends QueueableJob.Finalizer {
    public override void work() {
        FinalizerContext fctx = Async.getQueueableJobContext().finalizerCtx;
        if (fctx.getResult() == ParentJobResult.UNHANDLED_EXCEPTION) {
            Async.stopChain();
        }
    }
}
```

## When Async Lib itself fails

Everything above is about your job failing. If the **library** fails while
advancing the chain, that used to be invisible: a finalizer exception does not
show up on the `AsyncApexJob`, which still reads `Completed`, so a chain could
stop with no trace anywhere.

Async Lib now writes an `AsyncResult__c` row with `Status__c = FRAMEWORK_ERROR`
whenever it cannot advance a chain, and re-throws so the failure is not
swallowed. `ExceptionMessage__c` carries the underlying exception, the stack
trace, and where to go next:

```
Async Lib could not advance the chain: System.NullPointerException: ...

Check your job and QueueableJobSetting__mdt configuration against
https://async.beyondthecloud.dev first. If this looks like a library bug,
report it at https://github.com/beyond-the-cloud-dev/async-lib/issues
```

::: warning Written even when results are off

This row is written regardless of
`QueueableJobSetting__mdt.CreateResult__c`. Turning result creation off opts out
of routine bookkeeping, not out of being told the framework broke. It is the
only status that ignores that setting.

`FRAMEWORK_ERROR` rows are cleaned up on the `othersOlderThanDays(...)` track,
see [AsyncResult Cleanup](/explanations/asyncresult-cleanup).

:::

A governor limit hit by **your job** is fully covered. It never reaches a
`catch`, but the finalizer receives it and Async Lib records it like any other
failure:

```
System.AsyncException :: System.LimitException: Too many SOQL queries: 201
```

Note the recorded type is `System.AsyncException`, not `System.LimitException`.
`retryOn(LimitException.class)` will therefore not match it. Since Async Lib
writes the reason to `RetryHistory__c` when a type does not match, you will see
why rather than wondering where the retry went.

The one real gap is a governor limit hit **inside the finalizer itself**, for
example by an `onFinalFailure` override that burns through queries. Apex cannot
catch a `LimitException`, so there is no second finalizer to record it: the
`AsyncApexJob` reads `Completed` and no row is written. Keep `onFinalFailure`
cheap.

## Misconfiguration fails at enqueue, not later

Configuration mistakes are reported when you enqueue, in your own transaction,
rather than surfacing as a job that quietly does the wrong thing hours later.

An unknown `QueueableJobSetting__mdt.BackoffStrategy__c` throws instead of
silently running retries with no delay:

```
QueueableJobSetting__mdt.BackoffStrategy__c is "EXPONENTAIL" for "All", which is
not a known strategy. Use one of: FIXED, EXPONENTIAL, EXPONENTIAL_JITTER.
```

`RetryableExceptions__c` is different, and deliberately so. Entries there are
matched by name, and a typo would otherwise mean the job simply never retries.
We cannot reject unknown names up front, because a subscriber's own exception
class is not resolvable from inside the package. Instead, when a failure is not
retried because its type is not in the list, the reason is written to
`RetryHistory__c`:

```
AsyncTest.CustomException is not in retryOn(System.DmlException) - not retried
```

So a typo shows up on the result row rather than looking like retry silently not
working.

## Nothing is recorded for a discarded job

A job the framework discards produces no `AsyncResult__c` row. It never ran, and
from outside the failed transaction nobody ever held its id, so there is no
event to record. Salesforce does not tell you about a rolled-back
`System.enqueueJob` either.

What is recorded is the failure that caused it: the failing job's own
`AsyncResult__c` row, with `Status__c = FAILED`.

Watch for one case. With `rollbackOnJobExecuteFail()` the exception is swallowed,
so the `AsyncApexJob` reads **Completed** while the jobs the attempt chained have
vanished. The `AsyncResult__c` row still says `FAILED`, so check there rather
than the `AsyncApexJob`.
