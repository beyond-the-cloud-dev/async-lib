# Queueable API

Apex classes `QueueableBuilder.cls`, `QueueableManager.cls`, and
`QueueableJob.cls`.

For testing patterns and best practices, see
[Testing Async Jobs](/explanations/testing-async-jobs).

**Common Queueable example:**

```apex
QueueableJob job = new MyQueueableJob();
Async.Result result = Async.queueable(job)
	.priority(5)
	.delay(2)
	.continueOnJobExecuteFail()
	.enqueue();
```

Returns `result.customJobId` containing MyQueueableJob's unique Custom Job Id.

**Common QueueableJob class example:**

```apex
public class AccountProcessorJob extends QueueableJob {
  public override void work() {
    // Get job context
    Async.QueueableJobContext ctx = Async.getQueueableJobContext();
  }
}
```

**Common Finalizer class example:**

```apex
private class ProcessorFinalizer extends QueueableJob.Finalizer {
  public override void work() {
    // Get finalizer context
    FinalizerContext finalizerCtx = Async.getQueueableJobContext().finalizerCtx;
  }
}
```

## Methods

The following are methods for using Async with Queueable jobs:

[**INIT**](#init)

- [`queueable(QueueableJob job)`](#queueable)
- [`queueable()`](#queueable-no-args)

[**Build**](#build)

- [`asyncOptions(AsyncOptions asyncOptions)`](#asyncoptions)
- [`delay(Integer delay)`](#delay)
- [`priority(Integer priority)`](#priority)
- [`continueOnJobEnqueueFail()`](#continueonjobenqueuefail)
- [`continueOnJobExecuteFail()`](#continueonjobexecutefail)
- [`rollbackOnJobExecuteFail()`](#rollbackonjobexecutefail)
- [`retry(Integer maxRetries)`](#retry)
- [`backoff(Backoff backoff)`](#backoff)
- [`retryOn(Type exceptionType)`](#retryon)
- [`dependsOn(Async.Dependency dependency)`](#dependson)
- [`deepClone()`](#deepclone)
- [`chain()`](#chain)
- [`chain(QueueableJob job)`](#chain-next-job)
- [`asSchedulable()`](#asschedulable)
- [`mockId(String mockId)`](#mockid)

[**Execute**](#execute)

- [`enqueue()`](#enqueue)
- [`attachFinalizer()`](#attachfinalizer)

[**Context**](#context)

- [`getQueueableJobContext()`](#getqueueablejobcontext)
- [`getQueueableChainSchedulableId()`](#getqueueablechainschedulableid)
- [`getCurrentQueueableChainState()`](#getcurrentqueueablechainstate)

[**Chain control**](#chain-control)

- [`stopChain()`](#stopchain)
- [`skipJob(String customJobId)`](#skipjob)

### INIT

#### queueable

Constructs a new QueueableBuilder instance with the specified queueable job.

**Signature**

```apex
Async queueable(QueueableJob job);
```

**Example**

```apex
Async.queueable(new MyQueueableJob());
```

#### queueable (no args) {#queueable-no-args}

Constructs an empty QueueableBuilder so jobs can be added incrementally via
`chain(QueueableJob)`. Useful when the number of jobs to enqueue depends on
runtime conditions — calling `enqueue()` on a builder with zero jobs is a safe
no-op.

**Signature**

```apex
QueueableBuilder queueable();
```

**Example**

```apex
QueueableBuilder builder = Async.queueable();
if (needsJob1) {
	builder.chain(new Job1());
}
if (needsJob2) {
	builder.chain(new Job2());
}
if (needsJob3) {
	builder.chain(new Job3());
}
// Enqueues whatever was added; does nothing if none were.
builder.enqueue();
```

### Build

#### asyncOptions

Sets AsyncOptions for the queueable job. Cannot be used with delay().

**Signature**

```apex
QueueableBuilder asyncOptions(AsyncOptions asyncOptions);
```

**Example**

```apex
AsyncOptions options = new AsyncOptions();
Async.queueable(new MyQueueableJob())
	.asyncOptions(options);
```

#### delay

Sets a delay in minutes before the job executes. Cannot be used with
asyncOptions().

**Signature**

```apex
QueueableBuilder delay(Integer delay);
```

**Example**

```apex
Async.queueable(new MyQueueableJob())
	.delay(5);  // Execute in 5 minutes
```

#### priority

Sets the priority for the queueable job. Lower numbers = higher priority.

**Signature**

```apex
QueueableBuilder priority(Integer priority);
```

**Example**

```apex
Async.queueable(new MyQueueableJob())
	.priority(1);  // High priority
```

#### continueOnJobEnqueueFail

Allows the job chain to continue even if this job fails to enqueue.

**Signature**

```apex
QueueableBuilder continueOnJobEnqueueFail();
```

**Example**

```apex
Async.queueable(new MyQueueableJob())
	.continueOnJobEnqueueFail();
```

#### continueOnJobExecuteFail

Controls what happens to **this job's own work** when `work()` throws. It does
**not** control the chain. Remaining jobs still run, because chain progression
is driven by the finalizer, which always fires. To stop or branch the chain on
failure, use [`dependsOn(...)`](#dependson).

- **Without it (default):** the exception propagates, so the platform rolls back
  this job's DML and the `AsyncApexJob` is marked **Failed**.
- **With it:** the exception is caught, so the partial DML this job did before
  the failure is **committed** and the `AsyncApexJob` is marked **Completed**.

In both cases the job is still recorded as failed for
[`dependsOn(...)`](#dependson) outcome checks, and any [`retry(...)`](#retry)
still applies.

**Signature**

```apex
QueueableBuilder continueOnJobExecuteFail();
```

**Example**

```apex
Async.queueable(new MyQueueableJob())
	.continueOnJobExecuteFail();
```

#### rollbackOnJobExecuteFail

If `work()` throws, rolls this job's DML back to a savepoint taken before it
ran. Like [`continueOnJobExecuteFail()`](#continueonjobexecutefail) it handles
the failure (the exception is not re-thrown), so the chain keeps going. The
difference is that the partial DML is **discarded** instead of committed. You do
not need to also set `continueOnJobExecuteFail()`.

**Signature**

```apex
QueueableBuilder rollbackOnJobExecuteFail();
```

**Example**

```apex
Async.queueable(new MyQueueableJob())
	.rollbackOnJobExecuteFail();
```

#### retry

Opts the job into automatic retry on execution failure. `maxRetries` is the
number of retries **after** the first run (so `retry(3)` runs the job up to 4
times total). Retry is **off by default**, so without this call a failed job is
never retried. `maxRetries` must not exceed the framework safety limit of `10`;
a higher value (whether passed to `retry(...)` or configured via
`QueueableJobSetting__mdt`) throws an exception.

On each failed attempt the framework re-enqueues a fresh clone of the job with
an incremented attempt counter. By default **every** exception is retried. As a
best practice, narrow retries to the failures you know are worth re-running with
[`retryOn(...)`](#retryon). Retry composes with `continueOnJobExecuteFail`: once
retries are exhausted the chain behaves exactly as it would for a non-retry job.

When the job exhausts its retries, the per-attempt history (attempt number,
exception, computed delay) is aggregated into `AsyncResult__c.RetryHistory__c`
(when result creation is enabled via
`QueueableJobSetting__mdt.CreateResult__c`).

::: tip Idempotency A retried job re-runs `work()`, so make retried jobs
idempotent. For jobs carrying mutable member state, combine with
[`deepClone()`](#deepclone). :::

**Signature**

```apex
QueueableBuilder retry(Integer maxRetries);
```

**Example**

```apex
Async.queueable(new MyQueueableJob())
	.retry(3)
	.enqueue();
```

#### backoff

Sets the delay strategy between retries. Salesforce caps delayed enqueue at **10
integer minutes**, so every strategy is expressed in minutes and clamped to
`[0, 10]`. Without a backoff, retries are re-enqueued immediately.

| Strategy                           | Delay for attempt _n_ (base `b`)          |
| ---------------------------------- | ----------------------------------------- |
| `Backoff.fixed(b)`                 | `b`                                       |
| `Backoff.exponential(b)`           | `b * 2^(n-1)` (e.g. `1` → 1, 2, 4, 8, 10) |
| `Backoff.exponentialWithJitter(b)` | exponential plus random `0..b` jitter     |

**Signature**

```apex
QueueableBuilder backoff(Backoff backoff);
```

**Example**

```apex
Async.queueable(new MyQueueableJob())
	.retry(3)
	.backoff(Backoff.exponential(1)) // 1m, 2m, 4m
	.enqueue();
```

#### retryOn

Restricts retry to the listed exception types. Call multiple times to add more.
When omitted, retry applies to any exception.

**Signature**

```apex
QueueableBuilder retryOn(Type exceptionType);
QueueableBuilder retryOn(List<Type> exceptionTypes);
```

**Example**

```apex
Async.queueable(new MyQueueableJob())
	.retry(3)
	.retryOn(DmlException.class)
	.retryOn(CalloutException.class)
	.enqueue();
```

#### dependsOn

Makes the job conditional on another job's outcome. When the chain reaches a
dependent job whose dependency outcome does not match, that job is **skipped**,
along with anything that transitively depends on it. The rest of the chain still
runs. This is how you stop or branch a chain on failure; the
`...OnJobExecuteFail` flags do not affect chain progression.

The dependency target is identified by its auto-generated, always-unique
`customJobId`, so it is collision-proof even when the same code builds the chain
in a loop. Build the dependency with one of:

| Builder                       | Target                                             |
| ----------------------------- | -------------------------------------------------- |
| `Async.afterPrevious()`       | the immediately-preceding chained job              |
| `Async.after(Async.Result r)` | the job whose `Result` you captured when adding it |
| `Async.after(String id)`      | an explicit `customJobId`                          |

...combined with a required outcome:

| Outcome        | Runs the dependent when the target… |
| -------------- | ----------------------------------- |
| `.succeeded()` | completed without throwing          |
| `.failed()`    | threw during `work()`               |
| `.finished()`  | ran either way (success or failure) |

A job counts as _failed_ for these checks whenever its `work()` throws, no
matter how `continueOnJobExecuteFail` or `rollbackOnJobExecuteFail` are set.
Dependency targets must appear **earlier** in the chain than the jobs that
depend on them.

**Signature**

```apex
QueueableBuilder dependsOn(Async.Dependency dependency);
```

**Example**

```apex
// Linear gating reads cleanest with afterPrevious()
Async.queueable(new ExtractJob())
	.chain(new TransformJob())
		.dependsOn(Async.afterPrevious().succeeded())
	.enqueue();

// Fan-in / non-adjacent: capture the dependency's Result and reference it
Async.Result extract = Async.queueable(new ExtractJob()).chain();
Async.queueable(new TransformJob())
	.dependsOn(Async.after(extract).succeeded())
	.chain();
Async.queueable(new AlertOpsJob())
	.dependsOn(Async.after(extract).failed())
	.enqueue();
```

#### deepClone

Clones provided QueueableJob by value for all the member variables. By default
only primitive member variables (String, Boolean, ...) are cloned by value.
Deeper explanation is [here](/explanations/job-cloning).

::: warning Package Usage When using Async Lib as a package (`btcdev`
namespace), deep clone requires overriding `cloneForDeepCopy()` in your
subclass. See [Deep Clone in Packages](/explanations/deep-clone-in-packages).
:::

**Signature**

```apex
QueueableBuilder deepClone();
```

**Example**

```apex
Async.queueable(new MyQueueableJob())
	.deepClone();
```

#### chain

Adds the Queueable Job to the chain without enqueing it. All jobs in chain will
be enqueued once `enqueue()` method is invoked.

**Signature**

```apex
QueueableBuilder chain();
```

**Example**

```apex
Async.Result result = Async.queueable(new MyQueueableJob())
	.chain();
```

Returns `result.customJobId` containing MyQueueableJob's unique Custom Job Id.

#### chain next job

Adds the Queueable Job to the chain after previous job. All jobs in chain will
be enqueued once `enqueue()` method is invoked.

**Signature**

```apex
QueueableBuilder chain(QueueableJob job);
```

**Example**

```apex
Async.Result result = Async.queueable(new MyQueueableJob())
	.chain(new MyOtherQueueableJob());
```

Returns `result.customJobId` containing MyOtherQueueableJob's unique Custom Job
Id. To obtain MyQueueableJob's Id, use `chain()` method separately.

#### asSchedulable

Converts the queueable builder to a schedulable builder for cron-based
scheduling. See [Schedulable API](/api/schedulable) for scheduling options.

**Signature**

```apex
SchedulableBuilder asSchedulable();
```

**Example**

```apex
Async.queueable(new MyQueueableJob())
	.asSchedulable();
```

#### mockId

Sets a mock identifier for testing with AsyncMock. When the job executes during
a test, the framework will inject the corresponding mock context. See
[AsyncMock API](/api/async-mock) for details.

**Signature**

```apex
QueueableBuilder mockId(String mockId);
```

**Example**

```apex
// For queueable context mocking
AsyncMock.whenQueueable('account-creator')
	.thenReturn(new AsyncMock.MockQueueableContext());

Async.queueable(new AccountCreatorJob())
	.mockId('account-creator')
	.enqueue();

// For finalizer mocking, use mockId when attaching finalizer inside work()
// See AsyncMock API for finalizer patterns
```

### Execute

#### enqueue

Enqueues the queueable job with the configured options. Returns an Async.Result.

**Signature**

```apex
Async.Result enqueue();
```

**Example**

```apex
Async.Result result = Async.queueable(new MyQueueableJob())
	.priority(5)
	.enqueue();
```

**Result properties:**

| Property              | Description                                                                                                                                                                                                                                        |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `salesforceJobId`     | Salesforce Job Id of the actually-enqueued first-chain Queueable Job or Initial Queueable Chain Schedulable. `null` when `enqueue()` is called on an empty `Async.queueable()` builder with no jobs added.                                         |
| `customJobId`         | Unique Custom Job Id                                                                                                                                                                                                                               |
| `asyncType`           | `Async.AsyncType.QUEUEABLE`                                                                                                                                                                                                                        |
| `job`                 | The `QueueableJob` instance that the builder was finalized with. Useful for inspecting post-enqueue state, especially the cloned instance when `.deepClone()` was used. `null` when `enqueue()` is called on an empty `Async.queueable()` builder. |
| `queueableChainState` | Chain state object (see below)                                                                                                                                                                                                                     |

**`queueableChainState` properties:**

| Property              | Description                                                                                         |
| --------------------- | --------------------------------------------------------------------------------------------------- |
| `jobs`                | All jobs in chain including finalizers and processed jobs                                           |
| `nextSalesforceJobId` | Salesforce Job Id that will run next from chain                                                     |
| `nextCustomJobId`     | Custom Job Id that will run next from chain                                                         |
| `enqueueType`         | How the chain was enqueued: `EXISTING_CHAIN`, `NEW_CHAIN`, or `INITIAL_QUEUEABLE_CHAIN_SCHEDULABLE` |

#### attachFinalizer

Attaches a finalizer job to run after the current job completes. Can only be
called within a QueueableChain context.

**Signature**

```apex
Async.Result attachFinalizer();
```

**Example**

```apex
// Inside a QueueableJob's work() method
Async.Result result = Async.queueable(new MyFinalizerJob())
	.attachFinalizer();
```

Returns `result.customJobId` containing the finalizer's unique Custom Job Id.

### Context

#### getQueueableJobContext

Gets the current queueable job context, providing access to job information and
Salesforce QueueableContext.

**Signature**

```apex
Async.QueueableJobContext getQueueableJobContext();
```

**Example**

```apex
Async.QueueableJobContext ctx = Async.getQueueableJobContext();
```

**Context properties:**

| Property           | Description                                             |
| ------------------ | ------------------------------------------------------- |
| `ctx.currentJob`   | Current `QueueableJob` instance                         |
| `ctx.queueableCtx` | Salesforce `QueueableContext`                           |
| `ctx.finalizerCtx` | Salesforce `FinalizerContext` (available in finalizers) |

#### getQueueableChainSchedulableId

Gets the ID of the initial Queueable Chain Schedulable if the current execution
is part of a scheduled-based chain.

**Signature**

```apex
Id getQueueableChainSchedulableId();
```

**Example**

```apex
Id schedulableId = Async.getQueueableChainSchedulableId();
```

Returns the Id of the Initial Queueable Chain Schedulable.

#### getCurrentQueueableChainState

Gets details about the current Queueable Chain.

**Signature**

```apex
QueueableChainState getCurrentQueueableChainState();
```

**Example**

```apex
QueueableChainState currentChain = Async.getCurrentQueueableChainState();
```

**Chain state properties:**

| Property              | Description                                                        |
| --------------------- | ------------------------------------------------------------------ |
| `jobs`                | All jobs in chain including processed ones and finalizers          |
| `nextSalesforceJobId` | Salesforce Job Id that will run next (empty if chain not enqueued) |
| `nextCustomJobId`     | Custom Job Id that will run next from chain                        |
| `enqueueType`         | Empty until set during `enqueue()` method                          |

### Chain control

[`dependsOn(...)`](#dependson) is the **declarative** way to skip jobs based on
another job's outcome. For **imperative** control, where you decide at runtime
(based on the specific exception) whether to stop or skip, call these from a
running job or, better, from a **finalizer**.

::: tip Reacting to unhandlable failures When `work()` throws, your code in
`work()` never finishes, and an uncatchable governor-limit failure kills the
transaction entirely. A `QueueableJob.Finalizer` runs either way, with
`FinalizerContext.getResult()` reporting `UNHANDLED_EXCEPTION`, so it is the
right place to stop or reshape the chain after a failure. The framework
reconciles the failure from the `FinalizerContext`, so `dependsOn(...)` and your
finalizer logic both see the correct outcome even when our own `try/catch` could
not run. :::

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

#### stopChain

Skips every remaining (unprocessed) job in the current chain. Nothing else runs.

**Signature**

```apex
void stopChain();
```

**Example**

```apex
Async.stopChain();
```

#### skipJob

Skips the job with the given `customJobId` and any finalizers attached to it.
Jobs that [`dependsOn`](#dependson) the skipped job are skipped in turn. Throws
if no job in the chain has that id.

**Signature**

```apex
void skipJob(String customJobId);
```

**Example**

```apex
Async.skipJob(notificationsResult.customJobId);
```
