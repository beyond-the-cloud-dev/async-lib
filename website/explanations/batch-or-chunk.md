---
outline: deep
---

# Batch or Chunk?

## TL;DR

For new work over many records, use [`Async.chunk`](/api/chunk). It is a Queueable under the hood,
so it gets everything Async Lib does for Queueables: retry, backoff, a finalizer that survives limit
errors, dependencies, results, logging, requeue.

Keep `Database.Batchable` when you have one of the [reasons below](#when-a-batch-is-still-the-right-tool).
Async Lib will start it, schedule it, record its failures and run the failed records again. It will
not turn it into a Queueable, and this page explains why.

## Why Async Lib does not own the batch lifecycle

For a Queueable, Async Lib owns the whole run. Your class extends `QueueableJob`, the framework
wraps `work()`, and a platform Finalizer runs after every attempt, even one killed by a governor
limit. Retry, chain control and failure hooks all hang off that Finalizer.

A batch has nothing like it.

| What a retry needs | Queueable | Batch |
| ------------------ | --------- | ----- |
| Code that runs after a failed transaction, including a limit error | Transaction Finalizer | none. `finish()` runs once at the end, and if it throws, its own work is lost too |
| Knowing which records failed | the job holds its own state | only through `BatchApexErrorEvent`, delivered about a second later |
| Starting the next attempt as the original user | the Finalizer runs as that user | a trigger on the event runs as Automated Process, and so does anything it starts |

So a framework-owned batch base class would need a platform event trigger to see failures, a
Queueable to act on them as the right user, a waiting step between the two, and a hook to reload
records by id. That is a second engine with the same job as the first one, and it would still not
cover a `start()` that dies, because `finish()` never runs after it.

Salesforce describes the same direction in its own documentation: cursors combined with chained
Queueables are "a powerful alternative to Batch Apex", with no batch slot or flex queue to compete
for and with failure handling through a Transaction Finalizer. `ChunkJob` is that pattern, packaged.

We would rather make one engine very good than keep two half-equal ones. That is a decision, not a
backlog item.

## What a chunk run gives you

| | `Async.chunk` | `Database.Batchable` |
| --- | --- | --- |
| Rows per run | 50 million (cursor) | 50 million (`QueryLocator`) |
| Records per transaction | up to 2,000 | up to 2,000 |
| State between transactions | kept on the job, no interface needed | only with `Database.Stateful` |
| Retry and backoff per page | `.retry(n).backoff(...)` | none |
| Survives a governor limit error | yes, the Finalizer runs | no code of yours runs |
| Part of a chain, with `dependsOn` | yes | no |
| Throttling | `.delayBetweenChunks(minutes)` | none |
| Stop on first failure | `.stopRemainingChunksOnFailure()` | none |
| Concurrency ceiling | none of its own | 5 running, 100 waiting in the flex queue |
| Result per transaction | `AsyncResult__c`, success and failure | `AsyncResult__c` for failures only |

## When a batch is still the right tool

- **Apex managed sharing recalculation.** The platform asks for a `Database.Batchable` class.
- **Very high daily volume.** Cursors have org-wide daily limits a `QueryLocator` does not: 10,000
  cursors and 100 million cursor rows per day. A cursor counts its whole result set the moment it
  is opened.
- **A scope that is not a plain record query.** A custom `Iterable`, non-SObject items, aggregate
  results. `ChunkSource` pages over records.
- **Raw throughput on a huge, simple job.** A batch has less overhead between transactions than a
  chain of Queueables, and Salesforce runs a `QueryLocator` without subqueries on a faster path.
- **All-or-nothing capacity.** A batch does not start unless the whole job fits in what is left of
  the daily async limit. A chunk run finds out when it gets there.
- **You already have it.** A tested batch class that works is not a reason to rewrite anything.

Neither one is the answer to "this takes longer than two days". A cursor and a `QueryLocator` both
expire after two days.

## What Async Lib does for a batch

```apex
Async.batchable(new AccountCleanupBatch()).scopeSize(200).execute();
```

- **Start and schedule it** with the same fluent API as everything else. See
  [Batchable API](/api/batchable).
- **Record every failed scope**, including the ones killed by a governor limit, when the batch
  implements `Database.RaisesPlatformEvents`.
- **Tell your logger**, through the same `Async.OnJobFailed` you use for Queueables.
- **Run the failed records again**, through the batch's own `execute()`, with
  `Async.requeueBatchFailures(...)`.

All three are on [Batch Failures](/explanations/batch-failures).

What it will not do: retry a batch scope on its own, call a hook when a batch finishes, or put a
batch inside a Queueable chain. If you need those, that is the sign the work wants to be a
`ChunkJob`.

## Moving a batch to a chunk run

```apex
public class AccountCleanupBatch implements Database.Batchable<SObject> {
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator('SELECT Id FROM Account WHERE IsActive__c = false');
    }
    public void execute(Database.BatchableContext bc, List<Account> scope) {
        delete scope;
    }
    public void finish(Database.BatchableContext bc) {
    }
}
```

```apex
public class AccountCleanupJob extends ChunkJob implements Async.ChunkResettable, Async.Retryable {
    public override void work(List<SObject> chunk) {
        delete chunk;
    }
    public void resetBeforeNextChunk(Integer pageNumber) {
    }
    public void resetBeforeRetry(Integer attempt) {
    }
}

Async.chunk(
        new AccountCleanupJob(),
        ChunkSource.query('SELECT Id FROM Account WHERE IsActive__c = false')
    )
    .chunkSize(200)
    .retry(2)
    .enqueue();
```

`start()` becomes the `ChunkSource`, `execute()` becomes `work()`, and whatever `finish()` did
becomes the next job in the chain. The two empty methods are the job saying it keeps no state
between pages or attempts. Calling `.restoreStateOnNextChunk()` and `.restoreStateOnRetry()` on the
builder is the other way to answer. See [Job State Between Runs](/explanations/job-state-between-runs).

## What about Schedulable?

There is no framework-owned `Schedulable` base either, and no retry for a schedule. A schedule
that fails to fire is not retried, it fires again at its next time, and `SchedulableBuilder` with
`CronBuilder` already covers setting that up. Work that needs retry belongs in the job the schedule
starts: schedule a Queueable with `Async.queueable(job).asSchedulable()` and put `retry(n)` on it.
