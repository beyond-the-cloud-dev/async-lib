---
outline: deep
---

# AsyncResult Cleanup

## TL;DR

`AsyncResult__c` records accumulate with every tracked job and are never
deleted on their own. Async Lib ships a dormant `AsyncResultCleanupBatch`.
Schedule it once with explicit retention and old records get deleted daily:

```apex
Async.batchable(
        new AsyncResultCleanupBatch()
            .failedOlderThanDays(90)
            .othersOlderThanDays(30)
    )
    .asSchedulable()
    .name('AsyncResult Cleanup')
    .cronExpression(new CronBuilder().everyDay(3, 0))
    .schedule();
```

Nothing runs until you schedule it, and there are no default retention values.
Every track you want cleaned must be configured explicitly.

## Two Retention Tracks

Failed results are usually the ones you keep around for debugging, so they get
their own retention, independent from everything else.

| Track    | Matches `Status__c`                                                                        | Builder method                     |
| -------- | ------------------------------------------------------------------------------------------ | ---------------------------------- |
| Failed   | `FAILED`                                                                                    | `failedOlderThanDays(Integer days)` |
| The rest | `COMPLETED`, `SKIPPED_DEPENDENCY`, `SKIPPED_CHAIN_STOPPED`, `SKIPPED_CHUNK_STOPPED`, `SKIPPED_EXPLICIT`, `SKIPPED_DISABLED` | `othersOlderThanDays(Integer days)` |

Set one track, the other, or both. A track without a configured retention is
**never touched**:

```apex
// Delete failed results older than 90 days, keep everything else forever.
new AsyncResultCleanupBatch().failedOlderThanDays(90);

// Delete completed and skipped results older than 30 days, keep failed forever.
new AsyncResultCleanupBatch().othersOlderThanDays(30);

// Keep failed results three times longer than the rest.
new AsyncResultCleanupBatch().failedOlderThanDays(90).othersOlderThanDays(30);
```

## Rules

- Retention days must be greater than zero. `failedOlderThanDays(0)` or a
  `null` value throws an `IllegalArgumentException` immediately.
- At least one track must be configured. Running the batch with none throws
  when the batch starts.
- Use a retention of at least a few days so results from long-running or
  delayed chains are never deleted while their chain is still being
  reconciled.

## Running It Once, Ad Hoc

The same batch works without scheduling, for a one-off purge:

```apex
Async.batchable(new AsyncResultCleanupBatch().othersOlderThanDays(30)).execute();
```

For very large backlogs, raise the batch scope:

```apex
Async.batchable(new AsyncResultCleanupBatch().othersOlderThanDays(30))
    .scopeSize(2000)
    .execute();
```
