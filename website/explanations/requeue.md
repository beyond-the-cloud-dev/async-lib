---
outline: deep
---

# Requeue

## TL;DR

A job failed, you fixed whatever caused it, and now you want it to run again with the same input.
That is what requeue is for.

```apex
Async.requeue(resultId);
```

```apex
Async.RequeueSummary summary = Async.requeue(failedResultIds);
summary.requeued;              // the results that were replayed
summary.skipReasonByResultId;  // the rest, and why each one was skipped
summary.enqueueResult;         // the chain the replays run in
```

To make this possible, Async Lib stores a snapshot of the job on its `AsyncResult__c` record. That
is off by default, because the snapshot is a copy of whatever data the job was carrying, and you
should decide whether that belongs on a queryable object in your org.

## Turning it on

Set `StoreJobPayload__c` to `Yes` on the `All` record of `QueueableJobSetting__mdt`, or on a
record for a single job.

It is a picklist rather than a checkbox on purpose. A job record can say `No`, and that beats a
`Yes` on `All`. In practice the decision usually looks like "store payloads for everything, except
the one job that carries sensitive data", and a checkbox cannot express that.

## You do not need `CreateResult__c`

`CreateResult__c` writes a row for every job on every run, so most orgs with real volume keep it
off. If requeue depended on it, the orgs that need it most could not use it.

Instead, turning payload storage on writes a result row for **failed** and **skipped** jobs, no
matter what `CreateResult__c` says. Successful jobs still obey `CreateResult__c`, because there is
nothing to replay about a job that worked. The extra rows you get are bounded by your failure rate.

Skipped jobs are included because a job skipped over an unmet dependency never actually failed,
and once you fix the blocker it is exactly the one you want back.

## What the snapshot holds

The job as you handed it to `enqueue()`, before it ran. Not the failed attempt. A failed attempt
has already mutated its own state, and replaying from that is the bug
[the state gate](/explanations/job-state-between-runs) exists to prevent.

| Travels with the payload | Does not |
| ------------------------ | -------- |
| your own fields, `retry(n)`, `info(...)` | `backoff(...)`, `dependsOn(...)`, chain position, retry defaults from Custom Metadata |

So a replay retries the way the original did, but it starts a fresh chain, takes the retry
defaults from today's Custom Metadata, and does not carry dependencies from the old chain.

Chunk pages and finalizers are never stored. A page needs its source and a finalizer needs its
parent job, and neither of those survives on a record. They get `NotSerializable` on the row so you
can see that it was deliberate.

## Requeue replays data, not intent

::: warning Think before you requeue a job whose class you just changed

The payload was written by the class as it was when the job failed. It is rebuilt by the class as
it is now. If your fix changed the shape or the meaning of a field, the replay is not the job you
tested.

:::

There are two ways this goes wrong, and only one of them is loud.

**A renamed field arrives empty.** You renamed `accountIds` to `recordIds`. The payload still says
`accountIds`, so the rebuilt job starts with `recordIds` as `null`. It processes nothing, or throws
on the first dereference. A changed type, say `String` to `Integer`, fails at rebuild instead and
shows up in `skipReasonByResultId`. Either way, you notice.

**A field that kept its name and changed its meaning does the opposite.** The job carried
`Set<Id> accountIds` meaning "process these". Your fix changed `work()` so the set now means "skip
these". The payload rebuilds cleanly, the set holds the same ids, and the replay skips exactly the
records it was supposed to process. Nothing fails. Nothing is logged.

Requeue is the right tool when the fix was outside the job: an integration was down, a validation
rule was wrong, a permission was missing. When the fix changed what the job's own fields mean, do
not requeue. Enqueue it fresh with the input you want.

## On a packaged install, register a serializer

::: warning Required when Async Lib is installed as a package

JSON cannot cross a namespace boundary in either direction. Async Lib can neither store your job
nor rebuild it from inside its own namespace, regardless of whether your class is `public` or
`global`. Both halves have to run in your code.

:::

The class is ready to copy from
[`extras/classes/AsyncJobSerializer.cls`](https://github.com/beyond-the-cloud-dev/async-lib/tree/main/extras/classes):

```apex
global class AsyncJobSerializer implements btcdev.Async.JobSerializer {
    public String serialize(btcdev.QueueableJob job) {
        return JSON.serialize(job);
    }

    public btcdev.QueueableJob deserialize(String className, String payload) {
        return (btcdev.QueueableJob) JSON.deserialize(payload, Type.forName(className));
    }
}
```

Register it once, in `JobSerializerClass__c` on the `All` record. The class has to be `global` for
the same reason `LoggerClass__c` does: Async Lib resolves it by name from its own namespace, and
`Type.forName` reaches nothing else. Only the class, the methods stay `public`.

If you deployed the source instead, there is no boundary. Leave `JobSerializerClass__c` blank and
Async Lib converts the job itself. The full checklist for a packaged install is at
[Installing as a Package](/introduction/packaged-install).

## Reading the record

| Field | Holds |
| ----- | ----- |
| `JobPayload__c` | the serialized job |
| `PayloadSize__c` | its length in characters |
| `RequeueStatus__c` | whether it can be replayed |
| `RequeuedFrom__c` | the result this one was replayed from |

`JobPayload__c` is a Long Text Area, and Long Text cannot be filtered on. `WHERE JobPayload__c !=
null` does not even compile. That is why `RequeueStatus__c` exists, and it is what you select by.

| Status | Meaning |
| ------ | ------- |
| `Stored` | ready to replay |
| `Requeued` | already replayed |
| `TooLarge` | over 131,072 characters, nothing was stored |
| `NotSerializable` | the job could not be converted, or it is a chunk page or a finalizer. The reason is in `RetryHistory__c` |
| blank | payload storage was off for this job |

A job that hits `TooLarge` is almost certainly carrying full SObjects. Carry record ids and
re-query them inside `work()`. 131,072 characters holds roughly six thousand ids.

## Replaying in bulk

```apex
Set<Id> failed = new Map<Id, AsyncResult__c>([
    SELECT Id
    FROM AsyncResult__c
    WHERE RequeueStatus__c = 'Stored'
      AND CreatedDate = LAST_N_HOURS:2
]).keySet();

Async.requeue(failed);
```

All the replays go into **one chain** and run in sequence. That matters when requeue itself runs
from a Queueable, where only one job can be enqueued per transaction. One chain costs one slot, and
a replay that fails does not stop the ones after it.

There is a limit of 2,000,000 characters of payload per call, checked before any payload is loaded.
Over that, `Async.requeue` throws instead of dying halfway through. If you have more than that to
replay, order by `PayloadSize__c` and batch.

## The trail

```
R1 (failed) <- R2 (failed) <- R3
```

Each replay gets its own `AsyncResult__c` record in a new chain, linked back to its source by
`RequeuedFrom__c`. The source is marked `Requeued`. That mark is what makes a scheduled "replay
everything that failed" job safe: it never picks the same record up twice.

There is no cap on how long the trail can get. Requeue is something a person does after fixing
something, and `retry(n)` already covers the automated case with a bound. A cap here would only
punish whoever fixed the bug on the third try. If a replay fails again, that is worth a look
rather than another replay.

## If you put this behind a button, gate the button

`Async.requeue` is not permission-gated, the same as every other `Async` call. Called from Apex
that is fine: whoever can write the call could do anything else too. Once you expose it to end
users, through an `@AuraEnabled` method, a Flow action or a screen, the user gets to pick which
stored job runs, in system context, with the data it carried. Check a custom permission in your
controller before you call it.

## Limits

- Requeue replays one job, not its chain. The rest of the chain is not rebuilt.
- `AsyncResultCleanupBatch` deletes old records, so a replay is bounded by your retention window.
- `AsyncResultAccess` grants read on `JobPayload__c`. Review who holds that permission set before
  you turn storage on.

## Testing it

`AsyncMock.jobSettings(...)` injects the settings, so none of this needs real Custom Metadata:

```apex
AsyncMock.jobSettings(new List<QueueableJobSetting__mdt>{
    new QueueableJobSetting__mdt(
        QueueableJobName__c = 'All',
        StoreJobPayload__c = 'Yes'
    )
});
```
