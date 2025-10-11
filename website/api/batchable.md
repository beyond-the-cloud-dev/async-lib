# Batchable API

Apex classes `BatchableBuilder.cls` and `BatchableManager.cls`.

Common Batchable example:

```apex
Database.Batchable<Object> job = new MyBatchJob();
Async.Result result = new BatchableBuilder(job)
	.scopeSize(100)
	.execute();
System.debug('Batch job enqueued: ' + result);
```

## Methods

The following are methods for using Async with Batchable jobs:

[**INIT**](#init)

- [`batchable(Database.Batchable<Object> job)`](#batchable)

[**Build**](#build)

- [`scopeSize(Integer size)`](#scopesize)
- [`minutesFromNow(Integer minutes)`](#minutesfromnow)
- [`asSchedulable()`](#asschedulable)

[**Execute**](#execute)

- [`execute()`](#execute-1)

### INIT

#### batchable

Constructs a new BatchableBuilder instance with the specified batchable job.

**Signature**

```apex
Async batchable(Database.Batchable<Object> job);
```

**Example**

```apex
Async.batchable(new MyBatchJob());
```

### Build

#### scopeSize

Allows setting the scope size for the batch job.

**Signature**

```apex
BatchableBuilder scopeSize(Integer size);
```

**Example**

```apex
Async.batchable(new MyBatchJob())
	.scopeSize(100);
```

#### minutesFromNow

Allows scheduling the batch job to run after a specified number of minutes.

**Signature**

```apex
BatchableBuilder minutesFromNow(Integer minutes);
```

**Example**

```apex
Async.batchable(new MyBatchJob())
	.minutesFromNow(10);
```

#### asSchedulable

Converts the batch builder to a schedulable builder for cron-based scheduling. For scheduling, look into the [SchedulableBuilder](/api/schedulable.md) API.

**Signature**

```apex
SchedulableBuilder asSchedulable();
```

**Example**

```apex
Async.batchable(new MyBatchJob())
	.asSchedulable();
```

### Execute

#### execute

Executes the batch job with the configured options. Returns an Async.Result.

**Signature**

```apex
Async.Result execute();
```

**Example**

```apex
Async.batchable(new MyBatchJob())
	.scopeSize(100)
	.execute();
```

