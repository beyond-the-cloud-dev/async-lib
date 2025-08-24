# Queueable API

Apex classes `QueueableBuilder.cls`, `QueueableManager.cls`, and `QueueableJob.cls`.

Common Queueable example:

```apex
QueueableJob job = new MyQueueableJob();
Async.AsyncResult result = Async.queueable(job)
	.priority(5)
	.delay(2)
	.continueOnJobExecuteFail()
	.enqueue();
System.debug('Job enqueued: ' + result.customJobId);
```

## Methods

The following are methods for using Async with Queueable jobs:

[**INIT**](#init)

- [`queueable(QueueableJob job)`](#queueable)

[**Build**](#build)

- [`asyncOptions(AsyncOptions asyncOptions)`](#asyncoptions)
- [`delay(Integer delay)`](#delay)
- [`priority(Integer priority)`](#priority)
- [`continueOnJobEnqueueFail()`](#continueonjobequeuefail)
- [`continueOnJobExecuteFail()`](#continueonjobexecutefail)
- [`rollbackOnJobExecuteFail()`](#rollbackonjobexecutefail)
- [`asSchedulable()`](#asschedulable)

[**Execute**](#execute)

- [`enqueue()`](#enqueue)
- [`attachFinalizer()`](#attachfinalizer)

[**Context**](#context)

- [`getQueueableJobContext()`](#getqueueablejobcontext)
- [`getQueueableChainBatchId()`](#getqueueablechainbatchid)

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

Enqueues the queueable job with the configured options. Returns an Async.AsyncResult.

**Signature**

```apex
Async.AsyncResult enqueue();
```

**Example**

```apex
Async.AsyncResult result = Async.queueable(new MyQueueableJob())
	.priority(5)
	.enqueue();
```

#### attachFinalizer

Attaches a finalizer job to run after the current job completes. Can only be called within a QueueableChain context.

**Signature**

```apex
Async.AsyncResult attachFinalizer();
```

**Example**

```apex
// Inside a QueueableJob's work() method
Async.queueable(new MyFinalizerJob())
	.attachFinalizer();
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
Id batchId = Async.getQueueableChainBatchId();
System.debug('Current batch ID: ' + batchId);
```