# Queueable API

Apex classes `QueueableBuilder.cls`, `QueueableManager.cls`, and `QueueableJob.cls`.

For testing patterns and best practices, see [Testing Async Jobs](/explanations/testing-async-jobs).

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

[**Build**](#build)

- [`asyncOptions(AsyncOptions asyncOptions)`](#asyncoptions)
- [`delay(Integer delay)`](#delay)
- [`priority(Integer priority)`](#priority)
- [`continueOnJobEnqueueFail()`](#continueonjobenqueuefail)
- [`continueOnJobExecuteFail()`](#continueonjobexecutefail)
- [`rollbackOnJobExecuteFail()`](#rollbackonjobexecutefail)
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

Allows the job chain to continue even if this job fails during execution.

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

Rolls back any DML operations if this job fails during execution.

**Signature**

```apex
QueueableBuilder rollbackOnJobExecuteFail();
```

**Example**

```apex
Async.queueable(new MyQueueableJob())
	.rollbackOnJobExecuteFail();
```

#### deepClone

Clones provided QueueableJob by value for all the member variables. By default
only primitive member variables (String, Boolean, ...) are cloned by value.
Deeper explanation is [here](/explanations/job-cloning.md).

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

Returns `result.customJobId` containing MyOtherQueueableJob's unique Custom Job Id. To obtain MyQueueableJob's Id, use `chain()` method separately.

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

| Property | Description |
|----------|-------------|
| `salesforceJobId` | Salesforce Job Id of either Queueable Job or Initial Queueable Chain Schedulable (empty if job was not the enqueued one in chain) |
| `customJobId` | Unique Custom Job Id |
| `asyncType` | `Async.AsyncType.QUEUEABLE` |
| `queueableChainState` | Chain state object (see below) |

**`queueableChainState` properties:**

| Property | Description |
|----------|-------------|
| `jobs` | All jobs in chain including finalizers and processed jobs |
| `nextSalesforceJobId` | Salesforce Job Id that will run next from chain |
| `nextCustomJobId` | Custom Job Id that will run next from chain |
| `enqueueType` | How the chain was enqueued: `EXISTING_CHAIN`, `NEW_CHAIN`, or `INITIAL_QUEUEABLE_CHAIN_SCHEDULABLE` |

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

| Property | Description |
|----------|-------------|
| `ctx.currentJob` | Current `QueueableJob` instance |
| `ctx.queueableCtx` | Salesforce `QueueableContext` |
| `ctx.finalizerCtx` | Salesforce `FinalizerContext` (available in finalizers) |

#### getQueueableChainSchedulableId

Gets the ID of the initial Queueable Chain Schedulable if the current execution is part of
a scheduled-based chain.

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

| Property | Description |
|----------|-------------|
| `jobs` | All jobs in chain including processed ones and finalizers |
| `nextSalesforceJobId` | Salesforce Job Id that will run next (empty if chain not enqueued) |
| `nextCustomJobId` | Custom Job Id that will run next from chain |
| `enqueueType` | Empty until set during `enqueue()` method |
