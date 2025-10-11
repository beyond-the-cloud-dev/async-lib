# Queueable API

Apex classes `QueueableBuilder.cls`, `QueueableManager.cls`, and `QueueableJob.cls`.

Common Queueable example:

```apex
QueueableJob job = new MyQueueableJob();
Async.Result result = Async.queueable(job)
	.priority(5)
	.delay(2)
	.continueOnJobExecuteFail()
	.enqueue();

result.customJobId; // MyQueueableJob Custom Job Id
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
- [`chain()`](#chain)
- [`chain(QueueableJob job)`](#chain-next-job)
- [`asSchedulable()`](#asschedulable)

[**Execute**](#execute)

- [`enqueue()`](#enqueue)
- [`attachFinalizer()`](#attachfinalizer)

[**Context**](#context)

- [`getQueueableJobContext()`](#getqueueablejobcontext)
- [`getQueueableChainBatchId()`](#getqueueablechainbatchid)
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

Sets a delay in minutes before the job executes. Cannot be used with asyncOptions().

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

#### chain

Adds the Queueable Job to the chain without enqueing it.
All jobs in chain will be enqueued once `enqueue()` method is invoked.

**Signature**

```apex
QueueableBuilder chain();
```

**Example**

```apex
Async.Result result = Async.queueable(new MyQueueableJob())
	.chain();
result.customJobId; // MyQueueableJob unique Custom Job Id
```

#### chain next job

Adds the Queueable Job to the chain after previous job.
All jobs in chain will be enqueued once `enqueue()` method is invoked.

**Signature**

```apex
QueueableBuilder chain(QueueableJob job);
```

**Example**

```apex
Async.Result result = Async.queueable(new MyQueueableJob())
	.chain(new MyOtherQueueableJob());
result.customJobId; // MyOtherQueueableJob Unique Custom Job Id.
// To obtain MyQueueableJob Unique Custom Job Id use chain() method separately
```

#### asSchedulable

Converts the queueable builder to a schedulable builder for cron-based scheduling. For scheduling, look into the [SchedulableBuilder](/api/schedulable.md) API.

**Signature**

```apex
SchedulableBuilder asSchedulable();
```

**Example**

```apex
Async.queueable(new MyQueueableJob())
	.asSchedulable();
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

result.salesforceJobId; // MyQueueableJob Saleforce Job Id of either Queuable Job or Initial Scheduled Job, if MyQueueableJob was the enqueued one in chain, otherwise empty
result.customJobId; // MyQueueableJob Unique Custom Job Id.
result.asyncType; // Async.AsyncType.QUEUEABLE
result.isChained; // If job was chained
result.queueableChainState; // queueable chain state
result.queueableChainState.jobs; // All jobs that were chained or in chain, including finalizers and processed jobs
result.queueableChainState.nextSalesforceJobId; // Salesforce Job Id that will run next from chain
result.queueableChainState.nextCustomJobId; // Custom Job Id that will run next from chain
result.queueableChainState.enqueueType; // QueueableManager.EnqueueType - determine how the chain was enqueued, either added to currently running chain (EXISTING_CHAIN), enqueued as separate chain (NEW_CHAIN), or scheduled by initial job (INITIAL_SCHEDULED_BATCH_JOB)
```

#### attachFinalizer

Attaches a finalizer job to run after the current job completes. Can only be called within a QueueableChain context.

**Signature**

```apex
Async.Result attachFinalizer();
```

**Example**

```apex
// Inside a QueueableJob's work() method
Async.Result result = Async.queueable(new MyFinalizerJob())
	.attachFinalizer();

result.customJobId; // MyQueueableJob unique Custom Job Id
```

### Context

#### getQueueableJobContext

Gets the current queueable job context, providing access to job information and Salesforce QueueableContext.

**Signature**

```apex
Async.QueueableJobContext getQueueableJobContext();
```

**Example**

```apex
Async.QueueableJobContext ctx = Async.getQueueableJobContext();
QueueableJob currentJob = ctx.currentJob;
QueueableContext sfContext = ctx.queueableCtx;
```

#### getQueueableChainBatchId

Gets the ID of the QueueableChain batch job if the current execution is part of a batch-based chain.

**Signature**

```apex
Id getQueueableChainBatchId();
```

**Example**

```apex
Id batchId = Async.getQueueableChainBatchId(); // Initial Scheduled Batch Job
```

#### getCurrentQueueableChainState

Gets details about the current Queueable Chain.

**Signature**

```apex
QueueableChainState getCurrentQueueableChainState();
```

**Example**

```apex
QueueableChainState currentChain = Async.getCurrentQueueableChainState();
currentChain.jobs; // All jobs in chain including processed ones and finalizers
currentChain.nextSalesforceJobId; // Salesforce Job Id that will run next from chain, can be empty if chain not enqueued or from Chain context
currentChain.nextCustomJobId; // Custom Job Id that will run next from chain
currentChain.enqueueType; // empty, value set during enqueue() method
```