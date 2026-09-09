---
outline: deep
---

# Job State Between Runs

## TL;DR

A job object can run more than once. A retry re-runs it, and a chunk run re-runs it once per
page. Both times it keeps whatever the previous run left on it.

Async Lib makes you say what should happen. Two ways, pick either:

```apex
// You clear your own state
public class ImportJob extends QueueableJob implements Async.Retryable {
    private List<Id> inserted = new List<Id>();

    public override void work() { ... }

    public void resetBeforeRetry(Integer attempt) {
        inserted.clear();
    }
}
```

```apex
// Or Async Lib replays the job from the state it had when you enqueued it
Async.queueable(new ImportJob())
    .retry(3)
    .restoreStateOnRetry()
    .enqueue();
```

An **empty body is a valid answer**, and it is how you say "keep the state, that is what I want":

```apex
public void resetBeforeRetry(Integer attempt) {
}
```

That is exactly the 2.x behaviour. The next attempt starts with everything the failed one left
behind, which is what you want for a job that resumes where it stopped, or for a job that holds
nothing worth clearing. The only thing 3.0.0 changes is that you had to decide, rather than get
it by default without knowing.

There is deliberately no builder flag for this. The empty method lives on the job, where anyone
reading the job can see the decision, and it stays true no matter where the job is enqueued from.
A flag at the call site would have to be repeated at every call site and could disagree between
them.

## Why This Exists

Salesforce serializes your job when it is enqueued and hands the same object graph back on the
next run. Async Lib clones the job between attempts and between pages, but a clone of a dirty
job is still dirty.

So this happens without you noticing:

```apex
public class ImportJob extends QueueableJob {
    private List<Id> inserted = new List<Id>();

    public override void work() {
        for (Account a : accounts) {
            insert a;
            inserted.add(a.Id);
        }
        publish(inserted);   // attempt 2 publishes attempt 1's ids as well
    }
}
```

Attempt 1 inserts 50 records and throws. Attempt 2 starts with `inserted` already holding 50
ids, adds 50 more, and publishes 100. Nothing errors. The job reports success.

Chunking has the identical problem on a different axis. Page 2 starts with page 1's buffers.

## The Two Hazards

| Event | Interface | Hook | Builder alternative |
| ----- | --------- | ---- | ------------------- |
| a failed attempt is retried | `Async.Retryable` | `resetBeforeRetry(Integer attempt)` | `restoreStateOnRetry()` |
| a chunk run moves to the next page | `Async.ChunkResettable` | `resetBeforeNextChunk(Integer pageNumber)` | `restoreStateOnNextChunk()` |

They are separate on purpose. A chunk job that keeps a running total across pages but wants a
clean slate when a page is retried is a normal thing to write, and one combined hook could not
express it.

A job that both chunks and retries declares both:

```apex
public class ImportChunk extends ChunkJob
    implements Async.Retryable, Async.ChunkResettable {

    private List<Id> pending = new List<Id>();
    private Integer totalProcessed = 0;

    public override void work(List<SObject> page) { ... }

    public void resetBeforeRetry(Integer attempt) {
        pending.clear();          // the failed attempt's work is gone
    }

    public void resetBeforeNextChunk(Integer pageNumber) {
        pending.clear();          // totalProcessed deliberately survives
    }
}
```

## What Gets Restored

`restoreStateOnRetry()` and `restoreStateOnNextChunk()` take a deep copy of the job when it is
enqueued and replay from that copy.

Only **fields you declared** come back. Everything Async Lib owns is progression and is carried
forward from the live run, so a retry still knows it is attempt 3 and a chunk page still knows
where it is in the source.

| Carried forward from the live run | Restored to its enqueue-time value |
| --------------------------------- | ---------------------------------- |
| `retryAttempt`, `retryHistory`, backoff delay | every field your subclass declares |
| chunk position, page count, source | |
| job and chain ids, sequence | |
| failure info, skip status, processed flags | |

Because the chunk position is carried rather than copied, the `ChunkSource` is never serialized.
A `Database.Cursor` source works with `restoreStateOnNextChunk()` exactly like an in-memory one.

## Cost

The restore options take a deep copy, which costs roughly twice the job's size in heap while it
is being made. Measured, a 1 MB job needs about 2 MB, so the practical ceiling is around 2 MB of
job state from a synchronous caller.

The hooks cost nothing. If your reset is a couple of `clear()` calls, prefer the hook.

In a **namespaced package install** the deep copy needs one line of help from your namespace.
Override `cloneForDeepCopy()` on the job, or extend one of the ready-made base classes that do it
for you. The base classes are a convenience, not a requirement, and either route works. See
[Deep Clone in Packages](/explanations/deep-clone-in-packages).

The hooks need none of this, which is another reason to prefer them.

## Migrating From `resetForRetry()`

`resetForRetry()` is superseded and **no longer called**. Move its body:

```apex
// Before
public override void resetForRetry() {
    inserted.clear();
}

// After
public class ImportJob extends QueueableJob implements Async.Retryable {
    public void resetBeforeRetry(Integer attempt) {
        inserted.clear();
    }
}
```

The old method still exists and still compiles, because removing it would break the package
install in every org that referenced it. It just does nothing.

You will not miss this quietly. Any job configuring retry without declaring a reset throws at
enqueue, in your own transaction, so it fails in your tests the first time you run them.

## When The Gate Fires

At `.enqueue()` or `.chain()`, synchronously, before anything is sent to the queue:

- a job with `retry(n)` that neither implements `Async.Retryable` nor calls `restoreStateOnRetry()`
- a `ChunkJob` that neither implements `Async.ChunkResettable` nor calls `restoreStateOnNextChunk()`

Retry configured through `QueueableJobSetting__mdt` is gated too. Turning retry on for a job in
custom metadata cannot bypass the check.
