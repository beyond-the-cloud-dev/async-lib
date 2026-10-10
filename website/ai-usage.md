---
outline: deep
---

# Async Lib for AI Agents

The whole public surface on one page: entry points, every builder method, what you implement,
what you get back, configuration, and the mistakes agents make most. Written to be read once and
then copied from. For humans the rest of the docs go deeper; for agents there is also
[`/llms.txt`](https://async.beyondthecloud.dev/llms.txt) and
[`/llms-full.txt`](https://async.beyondthecloud.dev/llms-full.txt), which the build generates
from every page.

Names below are for a source deploy. On a packaged install prefix every class with `btcdev.`
(`btcdev.Async`, `btcdev.QueueableJob`) and every object and field with `btcdev__`. Details in
[Installing as a Package](/introduction/packaged-install).

## Entry points

| Call | Returns | Use it for |
| ---- | ------- | ---------- |
| `Async.queueable(QueueableJob job)` | `QueueableBuilder` | one job, or the start of a chain |
| `Async.queueable()` | `QueueableBuilder` | an empty builder to `.chain(job)` into; `enqueue()` starts whatever was chained earlier in the transaction, by anyone, and does nothing if nothing is waiting |
| `Async.chunk(ChunkJob job, ChunkSource source)` | `ChunkBuilder` | one job over many records, one page per transaction |
| `Async.batchable(Database.Batchable job)` | `BatchableBuilder` | a standard batch you have a reason to keep, with scope and delay; for new work prefer `Async.chunk` |
| `Async.schedulable(Schedulable job)` | `SchedulableBuilder` | a standard schedulable, with cron helpers |
| `Async.after(Result r)` / `Async.after(String customJobId)` / `Async.afterPrevious()` | `Async.Dependency` | the target of `dependsOn(...)`, finished with `.succeeded()`, `.failed()` or `.finished()` |
| `Async.stopChain()` | | inside a job or finalizer: skip every remaining job in the chain |
| `Async.skipJob(String customJobId)` | | inside a job or finalizer: skip one job and its finalizers |
| `Async.requeue(Id resultId)` / `Async.requeue(Set<Id> resultIds)` | `Async.RequeueSummary` | replay failed jobs from their `AsyncResult__c` records |
| `Async.requeueBatchFailures(Object batch, Id batchJobId, List<SObjectField> fieldsToReload)` / `(batch, batchJobId, List<String> fieldsToReload)` / `(batch, batchJobId, Async.BatchRecordLoader loader)` | `Async.RequeueSummary` | run the failed scopes of a batch again through its own `execute()`; the third argument is required and says how to reload the records |
| `Async.getQueueableJobContext()` | `Async.QueueableJobContext` | inside a job: the current job, `QueueableContext`, `FinalizerContext` |
| `Async.getCurrentQueueableChainState()` | `Async.QueueableChainState` | every job in the chain and what runs next |
| `Async.getQueueableChainSchedulableId()` | `Id` | the scheduled job id when the chain started through the 50-job overflow path |
| `Async.Backoff.fixed(m)` / `.exponential(m)` / `.exponentialWithJitter(m)` | `Backoff` | the same three as `Backoff.*`, safe to call inside a `QueueableJob` subclass |

## Builders

Every builder is fluent. `enqueue()` starts a chain, `chain()` adds to it without starting,
`enqueue()` on the last builder starts everything chained before it. Jobs chained and not yet
enqueued wait in one open chain shared by all code in the transaction, and every `enqueue()` in a
normal transaction starts a separate chain: [Chaining Across Services](/explanations/chaining-across-services).

### QueueableBuilder

| Method | What it does |
| ------ | ------------ |
| `priority(Integer)` | lower runs first |
| `delay(Integer minutes)` | 0 to 10, the platform cap; cannot combine with `asyncOptions` |
| `asyncOptions(AsyncOptions)` | duplicate-signature control; cannot combine with `delay` |
| `continueOnJobExecuteFail()` | swallow the exception, commit partial DML, chain continues |
| `rollbackOnJobExecuteFail()` | roll back this job's DML on failure, chain continues |
| `continueOnJobEnqueueFail()` | chain continues if this job cannot be enqueued |
| `retry(Integer maxRetries)` | 0 to 10 more attempts after the first; needs `Async.Retryable` or `restoreStateOnRetry()` |
| `backoff(Backoff)` | delay between attempts, minutes, clamped to 10 |
| `retryOn(Type)` / `retryOn(List<Type>)` | only these exception types retry; ANDed with `isRetryable()` |
| `restoreStateOnRetry()` | replay every attempt from the job as it was at enqueue |
| `deepClone()` | copy collections and objects, not just references, when cloning the job |
| `dependsOn(Async.Dependency)` | skip this job unless the target had that outcome |
| `info(String key, String value)` / `info(Map<String, String>)` | metadata that arrives on every lifecycle context |
| `mockId(String)` | key for `AsyncMock` in tests |
| `chain(QueueableJob next)` | add this job to the chain and hold `next` |
| `chunk(ChunkJob, ChunkSource)` | add this job, then continue as a `ChunkBuilder` |
| `asSchedulable()` | continue as a `SchedulableBuilder` |
| `chain()` | add to the chain, do not start it; returns `Async.Result` |
| `attachFinalizer()` | inside `work()`: run this job after the current one, success or failure |
| `enqueue()` | start the chain; returns `Async.Result` |

### ChunkBuilder

Everything from `QueueableBuilder` that makes sense for a run, plus:

| Method | What it does |
| ------ | ------------ |
| `chunkSize(Integer)` | records per page, default 200, capped by the source |
| `delayBetweenChunks(Integer minutes)` | wait between pages |
| `stopRemainingChunksOnFailure()` | a failed page ends the run; default is to continue |
| `keepChunkPages()` | keep every page's job in the chain state instead of dropping recorded ones |
| `restoreStateOnNextChunk()` | replay every page from the job as it was at enqueue |
| `chain(QueueableJob next)` / `chunk(ChunkJob, ChunkSource)` | continue the chain after the run |
| `chain()` / `enqueue()` | as above |

### ChunkSource

| Factory | Reads from |
| ------- | ---------- |
| `ChunkSource.of(List<SObject>)` | records already in memory |
| `ChunkSource.ofIds(Set<Id>)` | id-only records in memory; query the fields you need inside `work()` |
| `ChunkSource.query(String soql)` | a `Database.Cursor` over the query, system mode |
| `ChunkSource.query(soql, AccessLevel)` / `query(soql, Map<String, Object> binds)` / `query(soql, binds, AccessLevel)` | the same with user mode or bind variables |
| `ChunkSource.cursor(Database.Cursor)` | a cursor you opened yourself |

Your own: extend `ChunkSource`, implement `getNumRecords()` and `fetch(Integer position, Integer count)`.

### BatchableBuilder

| Method | What it does |
| ------ | ------------ |
| `scopeSize(Integer)` | records per `execute` |
| `execute()` | run now; returns `Async.Result` |
| `asSchedulable()` | continue as a `SchedulableBuilder` |
| `minutesFromNow(Integer)` | only with `asSchedulable().name(...).schedule()`: run once, that many minutes from now, instead of on a cron |

There is no `retry`, no finalizer and no `chain` for a batch, and there will not be. Those are
Queueable features; a `ChunkJob` has all of them. [Batch or Chunk?](/explanations/batch-or-chunk).

### SchedulableBuilder and CronBuilder

| Method | What it does |
| ------ | ------------ |
| `name(String)` | the scheduled job name, required |
| `cronExpression(String)` / `cronExpression(CronBuilder)` / `cronExpression(List<CronBuilder>)` | when; a list schedules one job per expression |
| `skipWhenAlreadyScheduled()` | no-op if a job with that name exists |
| `schedule()` | returns `List<Async.Result>` |

`CronBuilder` helpers: `everyHour(minute)`, `everyXHours(x, minute)`, `everyDay(hour, minute)`,
`everyXDays(x, hour, minute)`, `everyMonth(day, hour, minute)`, `everyXMonths(x, day, hour, minute)`,
`buildForEveryXMinutes(x)` (returns a list), and raw `second()`, `minute()`, `hour()`,
`dayOfMonth()`, `month()`, `dayOfWeek()`, `optionalYear()`. `getCronExpression()` gives the string.

## What you implement

```apex
public class ImportJob extends QueueableJob {
    private List<Id> recordIds;

    public ImportJob(List<Id> recordIds) {
        this.recordIds = recordIds;
    }

    public override void work() { /* the job */ }
}
```

| Member | On | When to override |
| ------ | -- | ---------------- |
| `void work()` | `QueueableJob` | always; the job body |
| `void work(List<SObject> page)` | `ChunkJob` | always; one page of the run |
| `Boolean isRetryable(Exception ex)` | `QueueableJob` | veto a retry for a specific exception; default `true` |
| `void onFinalFailure(Async.FailureContext ctx)` | `QueueableJob` | once, after the last attempt fails |
| `QueueableJob cloneForDeepCopy()` | `QueueableJob` | packaged installs only; see `extras/BaseQueueableJob` |
| `void resetBeforeRetry(Integer attempt)` | `implements Async.Retryable` | clear state before a retry; required by `retry(n)` unless `restoreStateOnRetry()` |
| `void resetBeforeNextChunk(Integer pageNumber)` | `implements Async.ChunkResettable` | clear state before the next page; required by every `ChunkJob` unless `restoreStateOnNextChunk()` |
| `onJobEnqueued` / `onJobSucceeded` / `onJobFailed` / `onRetryEnqueued` | `implements Async.OnJobEnqueued` etc. | lifecycle events, on the job or on a class registered in `LoggerClass__c` |
| `serialize(QueueableJob)` / `deserialize(String className, String payload)` | `implements Async.JobSerializer` | packaged installs using `requeue()`; see `extras/AsyncJobSerializer` |
| `List<SObject> load(Set<Id> failedRecordIds)` | `implements Async.BatchRecordLoader` | passed to `requeueBatchFailures` when a field list cannot reload the failed records |
| nothing | `implements Database.RaisesPlatformEvents`, on a `Database.Batchable` | standard marker; makes Async Lib record and log every failed scope of that batch |

### State between runs: answer once per question

A job object can run more than once, so Async Lib makes you say what happens to its fields in
between. Each question has two valid answers. Give exactly one. Give neither and `enqueue()` or
`chain()` throws, synchronously.

| The job | Question | Answer in the class | Or answer on the builder |
| ------- | -------- | ------------------- | ------------------------ |
| uses `retry(n)` | what carries over between attempts | `implements Async.Retryable` with `resetBeforeRetry(Integer attempt)` | `.restoreStateOnRetry()` |
| is a `ChunkJob` (always) | what carries over between pages | `implements Async.ChunkResettable` with `resetBeforeNextChunk(Integer pageNumber)` | `.restoreStateOnNextChunk()` |

- The interfaces are not mandatory and neither are the builder calls. One of the two per row is.
- A `ChunkJob` with `retry(n)` has both questions to answer.
- An empty method body is a real answer: "keep whatever is there". Use it for a job with no
  fields, and for one that accumulates on purpose, such as a running total across pages.
- A plain `QueueableJob` without `retry(n)` answers nothing.
- When writing a new job, default to the interface. The builder calls take a deep copy, which on
  a packaged install needs `extras/BaseQueueableJob` or `BaseChunkJob`. The interfaces need nothing.

Base classes: `QueueableJob.Finalizer` for a job attached with `attachFinalizer()`. Callouts are a
marker, `implements Database.AllowsCallouts`, on any of them.

Inside `work()` of a `ChunkJob`, `getRun()` gives `currentPageNumber()`, `hasRemainingPages()`,
`totalSize`, `chunkSize` and `remainingWorkSummary()`.

## What you get back

| Type | Fields |
| ---- | ------ |
| `Async.Result` | `salesforceJobId`, `customJobId`, `asyncType`, `job`, `queueableChainState` |
| `Async.QueueableChainState` | `jobs`, `nextSalesforceJobId`, `nextCustomJobId`, `enqueueType` |
| `Async.QueueableJobContext` | `currentJob`, `queueableCtx`, `finalizerCtx` |
| `Async.JobContext` | `customJobId`, `className`, `salesforceJobId`, `chainId`, `priority`, `retryAttempt`, `info` |
| `Async.FailureContext` | `retryOutcome`, `failure` (`type`, `message`, `stackTrace`), `customJobId`, `className`, `retryAttempt`, `maxRetries`, `retryHistory`, `nextAttemptDelayMinutes`, `info`, `asyncType`, `salesforceJobId`, and for a batch failure `batchPhase`, `batchScope`, `batchScopeTruncated` |
| `Async.RequeueSummary` | `requeued`, `skipReasonByResultId`, `enqueueResult` |
| `Async.Outcome` | `SUCCESS`, `FAILURE`, `COMPLETED` |
| `Async.RetryOutcome` | `NOT_CONFIGURED`, `NOT_RETRYABLE`, `EXHAUSTED` |
| `Async.AsyncType` | `QUEUEABLE`, `BATCHABLE`, `SCHEDULABLE` |

## Configuration: `QueueableJobSetting__mdt`

One record named `All` applies to every job; a record whose `QueueableJobName__c` is a class name
applies to that job. Wrong values degrade and record why, they never stop a job.

| Field | Type | Effect |
| ----- | ---- | ------ |
| `IsDisabled__c` | Checkbox | the job is skipped with `SKIPPED_DISABLED` |
| `CreateResult__c` | Checkbox | write an `AsyncResult__c` row for every outcome; for a batch, one row per failed scope |
| `MaxRetries__c` | Number | default retries, 0 to 10; only applied to jobs that declare how state resets |
| `BackoffStrategy__c` | Text | `FIXED`, `EXPONENTIAL`, `EXPONENTIAL_JITTER` |
| `BackoffBaseMinutes__c` | Number | base for the strategy |
| `RetryableExceptions__c` | Text | comma-separated exception type names |
| `LoggerClass__c` | Text | a `global` class implementing the lifecycle interfaces; batch failures arrive on `OnJobFailed` |
| `StoreJobPayload__c` | Picklist `Yes`/`No` | store a snapshot for `requeue()`; `No` on a job beats `Yes` on `All` |
| `JobSerializerClass__c` | Text | a `global` `Async.JobSerializer`, packaged installs only |

In tests, inject them: `AsyncMock.jobSettings(new List<QueueableJobSetting__mdt>{ ... })`.

## `AsyncResult__c`

One row per job, written after its last attempt, when `CreateResult__c` is on or a payload is
stored. A batch writes one row per failed scope and nothing for a successful one. Read access
through the `AsyncResultAccess` permission set.

| Field | Holds |
| ----- | ----- |
| `Status__c` | `COMPLETED`, `FAILED`, `SKIPPED_DEPENDENCY`, `SKIPPED_CHAIN_STOPPED`, `SKIPPED_CHUNK_STOPPED`, `SKIPPED_EXPLICIT`, `SKIPPED_DISABLED`, `FRAMEWORK_ERROR` |
| `ClassName__c`, `CustomJobId__c`, `SalesforceJobId__c`, `ChainId__c` | identity |
| `Result__c`, `ExceptionType__c`, `ExceptionMessage__c` | outcome |
| `RetryAttempts__c`, `RetryHistory__c` | one line per attempt, plus configuration warnings |
| `DependsOnResult__c`, `RequiredOutcome__c`, `ActualOutcome__c`, `SkipReason__c` | why a dependent job ran or was skipped |
| `JobPayload__c`, `PayloadSize__c`, `RequeueStatus__c`, `RequeuedFrom__c` | requeue |
| `BatchPhase__c`, `BatchScope__c`, `BatchScopeTruncated__c` | batch failures only: `START` / `EXECUTE` / `FINISH`, the failed record ids, and whether Salesforce cut that list short |

Old rows do not delete themselves. Schedule `AsyncResultCleanupBatch` with
`failedOlderThanDays(n)` and/or `othersOlderThanDays(n)`.

## `AsyncMock`

| Call | What it does |
| ---- | ------------ |
| `AsyncMock.whenQueueable(mockId).thenReturn(ctx \| jobId)` / `.thenThrow(ex)` | what the job sees, or fails with, when it runs |
| `AsyncMock.whenFinalizer(mockId).thenReturn(ctx \| ParentJobResult)` / `.thenThrow(ex)` | what the finalizer sees |
| `AsyncMock.whenQueueableDefault()` / `whenFinalizerDefault()` | fallback for jobs without a matching `mockId` |
| `AsyncMock.jobSettings(List<QueueableJobSetting__mdt>)` | inject Custom Metadata |
| `AsyncMock.reset()` | clear everything |
| `new AsyncMock.MockQueueableContext().setJobId(id)` / `new AsyncMock.MockFinalizerContext().setResult(r).setException(ex)` | hand-built contexts for calling `work()` directly |

Chain several `thenReturn` calls to script successive invocations.

## Recipes

### One job

```apex
Async.queueable(new ImportJob(recordIds)).enqueue();
```

### A chain where the second job runs only if the first succeeded

```apex
Async.queueable(new ExtractJob())
    .chain(new TransformJob())
        .dependsOn(Async.afterPrevious().succeeded())
    .chain(new NotifyJob())
        .dependsOn(Async.afterPrevious().finished())
    .enqueue();
```

### Retry with backoff, state cleared between attempts

```apex
public class SyncJob extends QueueableJob implements Async.Retryable {
    private List<Id> synced = new List<Id>();

    public override void work() { /* may throw CalloutException */ }

    public void resetBeforeRetry(Integer attempt) {
        synced.clear();
    }

    public override Boolean isRetryable(Exception ex) {
        return !ex.getMessage().contains('401');
    }
}

Async.queueable(new SyncJob())
    .retry(3)
    .backoff(Backoff.exponential(1))
    .retryOn(CalloutException.class)
    .enqueue();
```

### Many records, one page per transaction

```apex
public class RecalcJob extends ChunkJob implements Async.ChunkResettable {
    public override void work(List<SObject> page) {
        update page;
    }

    public void resetBeforeNextChunk(Integer pageNumber) {
    }
}

Async.chunk(new RecalcJob(), ChunkSource.query('SELECT Id FROM Account WHERE Recalc__c = true'))
    .chunkSize(200)
    .enqueue();
```

### Schedule

```apex
Async.queueable(new NightlyJob())
    .asSchedulable()
    .name('Nightly')
    .cronExpression(new CronBuilder().everyDay(2, 0))
    .skipWhenAlreadyScheduled()
    .schedule();
```

### React to a final failure, on the job or org-wide

```apex
public class ImportJob extends QueueableJob {
    public override void work() { /* ... */ }

    public override void onFinalFailure(Async.FailureContext ctx) {
        insert new IntegrationError__c(Message__c = ctx.failure.message, Attempts__c = ctx.retryAttempt);
    }
}

global class AsyncJobLogger implements Async.OnJobFailed {
    public void onJobFailed(Async.FailureContext ctx) {
        Logger.error(ctx.className + ' failed: ' + ctx.failure.message);
    }
}
// then QueueableJobSetting__mdt.LoggerClass__c = 'AsyncJobLogger' on the All record
```

### Several services, one chain

```apex
// in each service
Async.queueable(new SendWelcomeJob(accountIds)).chain();
Async.queueable(new ReviewContactJob(contactIds)).chain();

// once, as the last line of the entry point
Async.queueable().enqueue();
```

### A batch you keep, with its failures recorded and requeued

```apex
public class AccountSyncBatch implements Database.Batchable<SObject>, Database.RaisesPlatformEvents {
    public Database.QueryLocator start(Database.BatchableContext bc) { /* ... */ }
    public void execute(Database.BatchableContext bc, List<Account> scope) { /* ... */ }
    public void finish(Database.BatchableContext bc) { /* ... */ }
}
// QueueableJobSetting__mdt.CreateResult__c = true on All, or on a record named AccountSyncBatch

Id jobId = Async.batchable(new AccountSyncBatch()).scopeSize(200).execute().salesforceJobId;

// later, after fixing what broke
Async.requeueBatchFailures(new AccountSyncBatch(), jobId, new List<SObjectField>{ Account.Name });
```

### Test a job

```apex
@IsTest
static void failsCleanly() {
    AsyncMock.whenQueueable('import').thenThrow(new CalloutException('down'));

    Test.startTest();
    Async.queueable(new ImportJob(ids)).mockId('import').continueOnJobExecuteFail().enqueue();
    Test.stopTest();

    Assert.areEqual(1, [SELECT COUNT() FROM IntegrationError__c]);
}
```

## Gotchas

Things that read as bugs and are not, and things agents get wrong on the first try.

- **`retry(n)` throws at enqueue unless the job says what happens to its state.** Implement
  `Async.Retryable` or call `restoreStateOnRetry()`, one or the other. An empty `resetBeforeRetry`
  body is a valid answer. Same for every `ChunkJob`, retry or not, with `Async.ChunkResettable` or
  `restoreStateOnNextChunk()`. A bare `extends ChunkJob` with no builder call does not enqueue.
  The table is under [What you implement](#state-between-runs-answer-once-per-question).
  [Job State Between Runs](/explanations/job-state-between-runs).
- **More than 50 jobs is fine.** The chain switches to a scheduled starter past the platform's
  50-queueable limit on its own. Do not batch enqueues by hand.
- **Jobs chained inside `work()` join the running chain.** Use `Async.queueable(...).chain()` or
  `.enqueue()` from inside a job, never `System.enqueueJob`, or you spend the transaction's single
  enqueue slot on a job the chain does not know about.
- **A failed job does not stop the chain.** It stops its own work. Chain control is
  `dependsOn(...)`, `Async.stopChain()` or `Async.skipJob(...)`, and the safe place to call the
  last two is a finalizer. [Failures and the Chain](/explanations/failures-and-the-chain).
- **`Invalid conversion from runtime type ... to Datetime` in the debug log is expected.** The
  framework throws and catches it once per job to read the class name.
  [Expected Exceptions](/explanations/expected-exceptions-in-debug-logs).
- **`deepClone()` and `restoreStateOn*()` need a base class on a packaged install.** Copy
  `extras/BaseQueueableJob` and `BaseChunkJob`. Source deploys need nothing.
  [Deep Clone in Packages](/explanations/deep-clone-in-packages).
- **Inside a `QueueableJob` subclass write `Async.Backoff.exponential(1)`, not `Backoff.exponential(1)`.**
  The inherited `backoff` field shadows the type there.
- **Result rows are opt-in.** Nothing is written unless `CreateResult__c` is on, or a payload is
  stored and the job failed or was skipped. Do not query `AsyncResult__c` and expect a row.
- **`requeue()` replays data, not intent.** The payload is the job as it was enqueued, rebuilt by
  the class as it is now. If the fix renamed a field or changed what one means, enqueue fresh.
  [Requeue](/explanations/requeue).
- **Anything registered by name in Custom Metadata is `global` on a packaged install.**
  `LoggerClass__c`, `JobSerializerClass__c`. Class only, methods stay `public`.
- **A `ChunkJob` is not a batch.** One page per transaction, in sequence, inside the chain, with
  retry and dependencies. `Async.batchable(...)` is a plain `Database.Batchable` with a fluent
  wrapper. [Chunk](/api/chunk).
- **Default to `Async.chunk`, not `Async.batchable`, for new work over many records.** Batches get
  no retry, no finalizer and no chaining, on purpose: a batch has no Transaction Finalizer to build
  them on. Write a batch only for sharing recalculation, a non-record scope, or more than 100
  million cursor rows a day. [Batch or Chunk?](/explanations/batch-or-chunk).
- **`chain()` alone runs nothing.** Something has to call `enqueue()` before the transaction ends,
  and a chain that is never started is dropped without an error. Services call `chain()`, the entry
  point ends with `Async.queueable().enqueue()`.
  [Chaining Across Services](/explanations/chaining-across-services).
- **A batch failure is recorded only if the batch implements `Database.RaisesPlatformEvents`.**
  The row is written by a platform event trigger about a second after the scope fails, so the last
  one may not be there yet inside the batch's own `finish()`. In a test, catch what `Test.stopTest()` rethrows and
  call `Test.getEventBus().deliver()`. [Batch Failures](/explanations/batch-failures).
- **`requeueBatchFailures` needs to be told what to reload.** A failure stores ids only. Pass the
  fields `execute()` reads, an empty list for `Id` only, or an `Async.BatchRecordLoader`. `null`
  throws. It does not call `finish()` and does not retry on its own. A loader must be a saved
  class, not one declared inside an anonymous Apex script.
- **A logger hears batch failures as the Automated Process user.** Log there; do not enqueue work.
- **`delay()` and `asyncOptions()` are exclusive**, and `delay` tops out at 10 minutes.
