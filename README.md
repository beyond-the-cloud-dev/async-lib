# Async Lib

---

The Async Lib provides easy way for managing asynchronous processes in Salesforce.

## Features
- **Queueable Chain**: Eliminate the issues with "Too many queueable jobs" by using the `Async.queueable()` method to enqueue jobs in both synchronous and asynchronous context.
  - Framework will automatically handle the chaining of jobs, allowing you to enqueue multiple jobs without hitting the limit, in the same time using as many jobs as possible.
  - Each job will get its own Custom Job ID, which can be used to track the job status.
  - Async Result Custom Object will be created for each job, allowing you to track the status of each job.
  - Support for finalizers, which are executed after the job is processed, allowing you to handle any finalization logic.
- **Schedulable Jobs**: Schedule jobs to run at specific times using the `Async.schedulable()` method.
  - Convert any `QueueableJob` or `Database.Batchable` into a schedulable job, by using the `asSchedulable()` method.
  - Support easier cron expressions using the `CronBuilder` class.
- **Batchable Jobs**: Execute batch jobs using the `Async.batchable()` method.
- **Custom Metadata Configuration**: Configure the QueueableJob settings using the `QueueableJobSettings__mdt` custom metadata type to enable or disable jobs, and to control the creation of Async Result records.
- **Custom Object for Async Results**: The `AsyncResult__c` custom object is created for each processed queueable job, allowing you to track the chained job status and details.

## Queueable

### Usage

1. Create a class that extends `QueueableJob`.
```apex
// QueueableJob class example
public class MyQueueableJob extends QueueableJob {
    public override void work() {
        // To access the current job context
        Async.QueueableJobContext ctx = Async.getQueueableJobContext();
        // Your logic here
    }
}
```
2. Enqueue the job using the `Async.queueable()` method.
```apex
// QueueableJob enqueue example 
Async.queueable(new MyQueueableJob())
    .enqueue();
```
3. Optionally, you can set various properties on the job, such as `delay`, `priority`,  `asyncOptions` and behaviour on error.
```apex
// QueueableJob enqueue example with options
Async.queueable(new MyQueueableJob())
    .delay(10) // Delay in minutes
    .priority(10) // Set job priority, lower number means higher priority
    .asyncOptions(new AsyncOptions()) // Set async options
    .continueOnJobEnqueueFail() // Continue on job enqueue failure
    .continueOnJobExecuteFail() // Continue on job execution failure
    .rollbackOnJobExecuteFail() // Rollback on job execution failure
    .enqueue();
```
4. To access the current job context, use `Async.getQueueableJobContext()` within the `work()` method of your job class.
```apex
// Accessing the current job context
Async.QueueableJobContext ctx = Async.getQueueableJobContext();
ctx.currentJob; // The current QueueableJob instance
ctx.queueableCtx; // The QueueableContext instance
ctx.finalizerCtx; // The FinalizerContext instance
```
5. If you need to handle finalization logic, you can implement the `FinalizerContext` in your job class.
```apex
// FinalizerContext example
public class MyQueueableJobFinalizer extends QueueableJob.Finalizer {
    public override void work() {
        // Finalization logic here
        Async.QueueableJobContext ctx = Async.getQueueableJobContext();
        ctx.finalizerCtx; // Access the finalizer context
        // Access the job context and perform finalization
    }
}
```
6. Attach the finalizer job in the QueueableJob context.
```apex
// Enqueueing a finalizer job
Async.queueable(new MyQueueableJobFinalizer())
    .attachFinalizer();
```

### Class Definitions

```apex
// QueueableJob class example
public class MyQueueableJob extends QueueableJob {
    public override void work() {
        // To access the current job context
        Async.QueueableJobContext ctx = Async.getQueueableJobContext();
        // Your logic here
    }
}
```

```apex
// QueueableJob with callouts class example
public class MyQueueableJob extends QueueableJob.AllowsCallouts {
    public override void work() {
        // To access the current job context
        Async.QueueableJobContext ctx = Async.getQueueableJobContext();
        // Your logic here
    }
}
```

```apex
// Finalizer class example
public class MyQueueableJobFinalizer extends QueueableJob.Finalizer {
    public override void work() {
        // To access the current job context
        Async.QueueableJobContext ctx = Async.getQueueableJobContext();
        // Your logic here
    }
}
```

```apex
// QueueableJobContext definition
public class QueueableJobContext {
    public QueueableJob currentJob; // The current QueueableJob instance being processed
    public QueueableContext queueableCtx; // The QueueableContext instance for the current job
    public FinalizerContext finalizerCtx; // The FinalizerContext instance for the current job, if applicable
}
// QueueableJob defnition
public abstract class QueueableJob implements Queueable, Comparable {
    public Id salesforceJobId; // The Salesforce job ID of the processed job
    public String customJobId; // The custom job ID generated by the framework
    public String className; // The name of the class that implements QueueableJob
    public String uniqueName; // A unique name for the job, used to identify the job in the queue
    public Integer delay; // Delay in minutes before the job is executed
    public Integer priority; // Priority of the job, lower number means higher priority
    public AsyncOptions asyncOptions; // Options for the job execution
    public Boolean isProcessed = false; // Flag to indicate if the job has been processed
    public Boolean continueOnJobEnqueueFail = false; // Flag to continue on job enqueue failure
    public Boolean continueOnJobExecuteFail = false; // Flag to continue on job execution failure
    public Boolean rollbackOnJobExecuteFail = false; // Flag to rollback on job execution failure
    public QueueableContext queueableCtx; // The QueueableContext instance for the job

    public String parentCustomJobId; // The custom job ID of the parent job, used for finalizers
    public FinalizerContext finalizerCtx; // The FinalizerContext instance for the job
    public Boolean isFinalizer { // Flag to indicate if the job is a finalizer
        get {
            return String.isNotBlank(parentCustomJobId);
        }
    }
    ...
}
// AsyncResult definition
public class AsyncResult {
    public Id salesforceJobId; // The Salesforce job ID of the processed job
    public String customJobId; // The custom job ID generated by the framework
    public Boolean isChained; // Flag to indicate if the job is part of a chain
}
```

## Batchable

### Usage
1. Create a standard Batchable class that implements `Database.Batchable`.
2. Use the `Async.batchable()` method to execute the batch job.
```apex
// Batch execute example
Async.batchable(new MyBatchableJob())
    .execute();
```
3. Optionally, you can set `scopeSize` or `minutesFromNow`, but the latter can be used only when sheduling.
```apex
// Batch execute example with scope size
Async.batchable(new MyBatchableJob())
    .scopeSize(100) // Set the scope size for the batch job
    .execute();

// Batch schedule example with minutesFromNow
Async.batchable(new MyBatchableJob())
    .minutesFromNow(10) // Schedule the batch job to run in 10 minutes
    .asSchedulable() // Convert BatchableJob to Schedulable
    .name('My Scheduled Batch Job') // Set a name for the scheduled job - required
    // No CRON expression set since we are using minutesFromNow
    .schedule();
```

## Schedulable

### Usage
1. Use Batchable or QueueableJob class or create a standard Schedulable class that implements `Schedulable`.
2. If using Batchable or QueueableJob, ensure it uses `asSchedulable()` method to convert it into a Schedulable job.
```apex
// BatchableJob as Schedulable example
Async.batchable(new MyBatchableJob())
    ... // further configuration of batchable job
    .asSchedulable() // Convert BatchableJob to Schedulable
    ... // further configuration of scheduled job

// QueueableJob as Schedulable example
Async.queueable(new MyQueueableJob())
    ... // further configuration of queeuable job
    .asSchedulable() // Convert QueueableJob to Schedulable
    ... // further configuration of scheduled job
```
3. Use the `Async.schedulable()` method to schedule the job.
```apex
// Schedulable execute example
Async.schedulable(new MySchedulableJob())
    .name('My Scheduled Job') // Set a name for the scheduled job - required
    .cronExpression('0 0 12 * * ?') // Set a cron expression for scheduling - required
    .schedule();
```
4. Set Cron expression to be either a valid cron expression or a valid cron builder instance.
```apex
// Example of using CronBuilder via String
.cronExpression('0 0 12 * * ?')
// Example of using CronBuilder
.cronExpression(
    new CronBuilder()
        .buildForEveryXMinutes(10) // Build a cron expression to run every 10 minutes
)
// Example of using CronBuilder with a specific time
.cronExpression(
    new CronBuilder()
        .buildForEveryXHours(5, 25) // Build a cron expression to run every 5 hours starting at 25 minutes past the hour
)
```

## Async Result

Custom Object `AsyncResult__c` is created for each QueueableJob enabled in configuration that is processed. It contains the following fields:
- `CustomJobId__c`: The custom job ID generated by the framework.
- `SalesforceJobId__c`: The Salesforce job ID of the processed job. This can be used to check the job details directly in Salesforce.
- `Result__c`: The status of the job (`SUCCESS`, `UNHANDLED_EXCEPTION`).

## Queueable Job Settings

Custom Metadata Type `QueueableJobSettings__mdt` is used to configure the QueueableJob settings. It contains the following fields:
- `QueueableJobName__c`: The name of the QueueableJob.
- `IsDisabled__c`: Boolean field to indicate if the QueueableJob is disabled.
- `CreateResult`: Boolean field to indicate if the AsyncResult should be created for the job.

There is a default *Queueable Job Settings* record called `All` created in the package, which can be used to configure the default settings for all QueueableJobs.

## Deploy to Salesforce

<a href="https://githubsfdeploy.herokuapp.com?owner=beyond-the-cloud-dev&repo=async-lib&ref=main">
  <img alt="Deploy to Salesforce"
       src="https://raw.githubusercontent.com/afawcett/githubsfdeploy/master/deploy.png">
</a>

## Contributors

<a href="https://github.com/beyond-the-cloud-dev/async-lib/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=beyond-the-cloud-dev/async-lib" />
</a>

# License notes:
- For proper license management each repository should contain LICENSE file similar to this one.
- each original class should contain copyright mark: © Copyright 2025, Beyond The Cloud Dev Authors