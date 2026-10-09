---
outline: deep
---

# Chaining Across Services

## TL;DR

Several services in one transaction each want to run something in the background, and you want
it all in one chain. Let each service call `chain()`, and start the chain once, at the entry point.

```apex
// AccountService
Async.queueable(new SendWelcomeJob(accountIds)).chain();

// ContactService
Async.queueable(new ReviewContactJob(contactIds)).chain();

// the entry point: trigger handler, controller, invocable. Last line.
Async.queueable().enqueue();
```

One chain, one `System.enqueueJob`, both jobs in it. Nobody passes a builder around, and no service
needs to know who else has work.

This is a choice, not a requirement. Each service can just as well call `enqueue()` itself and get
its own chain. Read on for what the difference is.

## How jobs end up in a chain

Async Lib holds one **open chain** at a time: the jobs that were chained and not started yet.
`chain()` adds to it. `enqueue()` adds to it and starts it. What happens next depends on where the
code is running.

| Where | What `enqueue()` does | Then |
| ----- | --------------------- | ---- |
| Normal transaction: trigger, controller, anonymous Apex | starts the open chain with one `System.enqueueJob` | the open chain is empty again. The next `chain()` or `enqueue()` begins a new one |
| Normal transaction, past the 50 `enqueueJob` limit | hands the open chain to a scheduled starter | later jobs in the transaction join that same chain |
| Inside a running Async Lib job | adds to the chain that is running | nothing to start. The platform allows a running Queueable one enqueue, and the chain already uses it |

So a transaction can start several chains, and that is fine:

```apex
Async.queueable(new JobA()).enqueue();   // chain 1: JobA
Async.queueable(new JobB()).enqueue();   // chain 2: JobB, runs in parallel with chain 1
```

And it can put the same jobs in one chain, where they run one after the other:

```apex
Async.queueable(new JobA()).chain();
Async.queueable(new JobB()).enqueue();   // one chain: JobA, then JobB
```

The open chain is shared by all code in the transaction. A builder is not a container: passing
`Async.queueable()` from service to service and calling `builder.chain(job)` on it puts the jobs in
the same open chain that a bare `Async.queueable(job).chain()` would.

## One chain or several

| | One chain | A chain per service |
| --- | --- | --- |
| Services call | `chain()` | `enqueue()` |
| Jobs run | in sequence, in the order chained | in parallel, in no fixed order |
| `dependsOn(...)` between the services' jobs | works | not possible, they are different chains |
| `enqueueJob` calls used | one | one per service |
| A slow job | holds up the ones behind it | holds up nothing else |

Pick one chain when order matters, when one job depends on another, or when the work touches the
same records and should not run at the same time. Pick separate chains when the jobs are
independent and you want them to run as soon as they can.

## The one-chain pattern

**Services call `chain()`. The entry point calls `enqueue()` once, last.**

| Call | Adds its job | Starts the open chain |
| ---- | ------------ | --------------------- |
| `Async.queueable(job).chain()` | yes | no |
| `Async.queueable(job).enqueue()` | yes | yes, with everything chained before it |
| `Async.queueable().enqueue()` | nothing to add | yes, if anything is waiting. Otherwise it does nothing |

`Async.queueable().enqueue()` is safe to call when nothing was chained, and safe to call twice.
The second call finds nothing waiting. That makes it a good last line for an entry point that does
not know whether any service had work to do.

::: tip Changed in 3.1.0
Before 3.1.0 an empty builder never started anything, so the last line above silently dropped
every job the services had chained. If you worked around that by enqueueing a real job last, your
code keeps working unchanged.
:::

## What to watch for

**`chain()` with no `enqueue()` runs nothing.** The open chain lives in memory for the length of
the transaction. If nothing starts it, it is gone when the transaction ends, without an error. Apex
has no end-of-transaction hook, so Async Lib cannot catch this for you. A test can:

```apex
Test.startTest();
AccountTriggerHandler.run(accounts);
Assert.areEqual(
    0,
    Async.getCurrentQueueableChainState().jobs.size(),
    'Something was chained and never enqueued.'
);
Test.stopTest();
```

Make the check before `Test.stopTest()`. After it, the state describes the chain that just ran.

**Someone else's `enqueue()` starts your chained jobs too.** If one service calls `enqueue()` in
the middle, every job chained so far goes with it, and whatever is chained afterwards lands in a
new chain. Nothing is lost as long as a later `enqueue()` follows, but you get two chains where you
expected one. Keeping `enqueue()` out of the services avoids it.

**A trigger runs once per 200 records.** Loading 1,000 records fires the trigger five times. If the
handler ends with `Async.queueable().enqueue()`, you get five chains, each holding the jobs for its
own 200 records. Nothing is duplicated, and going past 50 enqueues is handled for you. If you want
one chain for the whole load, do not enqueue in the handler. Chain there, and enqueue from the code
that owns the whole operation.

**Trigger recursion duplicates jobs the same way it duplicates anything.** A trigger that fires
again on the same records, because a flow or another trigger updated them, chains the same job
again. Async Lib cannot tell that from a job you meant to run twice. Guard it the way you guard any
other side effect of a recursive trigger.

**Inside a running job you do not need `enqueue()` at all.** The chain is already running, and
anything chained from `work()` joins it. `Async.queueable().enqueue()` there does nothing. See
[Failures and the Chain](/explanations/failures-and-the-chain) for what happens to those jobs when
`work()` throws.

## Ordering and dependencies across services

Jobs in one chain run in the order they were chained, unless `priority(...)` says otherwise.

A service that needs another service's job to finish first can depend on it, because `chain()`
returns the job's id:

```apex
// AccountService
Async.Result welcome = Async.queueable(new SendWelcomeJob(accountIds)).chain();

// ContactService, given that result
Async.queueable(new ReviewContactJob(contactIds))
    .dependsOn(Async.after(welcome).succeeded())
    .chain();
```
