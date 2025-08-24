---
outline: deep
---

# Getting Started

Async Lib is a powerful Salesforce Apex framework that provides an elegant solution for managing asynchronous processes. It eliminates common limitations like "Too many queueable jobs" errors and offers a unified API for queueable, batchable, and schedulable jobs.

## Why Async Lib?

### Salesforce Limits

<table>
    <thead>
        <tr>
            <th>Apex Context</th>
            <th>Queueable</th>
            <th>Future</th>
            <th>Batch</th>
            <th>Schedule</th>
        </tr>
    </thead>
    <tbody>
        <tr>
            <td><strong>Synchronous</strong> or <strong>Scheduled*</strong> process</td>
            <td>50</td>
            <td>50</td>
            <td rowspan="3">100 in <strong>Holding</strong> status<br/>5 in <strong>Queued</strong> or <strong>Active</strong> status</td>
            <td rowspan="4">100</td>
        </tr>
        <tr>
            <td><strong>Queueable</strong> job</td>
            <td>1</td>
            <td>50</td>
        </tr>
        <tr>
            <td><strong>@future</strong> method call</td>
            <td>1</td>
            <td>0</td>
        </tr>
        <tr>
            <td><strong>Batch</strong> job</td>
            <td>1</td>
            <td>0</td>
            <td>As above in <strong>finish()</strong> batch method. For <strong>start()</strong> and <strong>execute()</strong> methods, the limit is 0.</td>
        </tr>
    </tbody>
</table>

### Key Benefits

- **🚀 Eliminates Queueable Limits**: Automatically handles "Too many queueable jobs" by intelligent chaining and batch overflow
- **🎯 Unified API**: Single, consistent interface for all async job types (Queueable, Batchable, Schedulable)
- **⚡ Smart Prioritization**: Jobs execute based on priority with automatic sorting
- **🛡️ Advanced Error Handling**: Built-in error recovery, rollback options, and continuation strategies
- **📊 Job Tracking**: Comprehensive tracking with custom job IDs and result records
- **⚙️ Configuration-Driven**: Control job behavior through custom metadata without code changes
- **🔗 Support Finalizers**: Execute cleanup logic after job completion with full context

```

## Core Concepts

### 1. QueueableJob Base Class

All queueable jobs extend the `QueueableJob` abstract class:

```apex
public class MyQueueableJob extends QueueableJob {
    public override void work() {
        // Your business logic here
        System.debug('Processing job: ' + Async.getQueueableJobContext().currentJob.customJobId);
    }
}
```

### 2. Builder Pattern API

All job types use a fluent builder pattern:

```apex
// Queueable Job
Async.queueable(new MyQueueableJob())
    .priority(10)
    .delay(5)
    .enqueue();

// Batch Job
Async.batchable(new MyBatchJob())
    .scopeSize(100)
    .execute();

// Schedulable Job
Async.schedulable(new MySchedulableJob())
    .name('Daily Cleanup')
    .cronExpression('0 0 2 * * ? *')
    .schedule();
```

### 3. Automatic Job Chaining

When queueable limits are reached, Async Lib automatically switches to scheduled-batch-based execution, ensuring your jobs always run without hitting Queueable platform limits.

## Your First Queueable Job

Let's create a simple job that processes accounts:

### Step 1: Create Your Job Class

```apex
public class AccountProcessorJob extends QueueableJob {
    private List<Id> accountIds;
    
    public AccountProcessorJob(List<Id> accountIds) {
        this.accountIds = accountIds;
    }
    
    public override void work() {
        // Get job context
        Async.QueueableJobContext ctx = Async.getQueueableJobContext();
        System.debug('Processing job: ' + ctx.currentJob.customJobId);
        
        // Process accounts
        List<Account> accounts = [SELECT Id, Name FROM Account WHERE Id IN :accountIds];
        for (Account acc : accounts) {
            acc.Description = 'Processed by ' + ctx.currentJob.className;
        }
        update accounts;
        
        System.debug('Processed ' + accounts.size() + ' accounts');
    }
}
```

### Step 2: Enqueue the Job

```apex
// Get some account IDs
List<Id> accountIds = new List<Id>{
    '0013000000abcdef',
    '0013000000ghijkl'
};

// Enqueue the job
Async.AsyncResult result = Async.queueable(new AccountProcessorJob(accountIds))
    .priority(5)
    .enqueue();

System.debug('Job enqueued with ID: ' + result.customJobId);
```

## Error Handling

Async Lib provides sophisticated error handling options:

```apex
Async.queueable(new MyJob())
    .continueOnJobEnqueueFail()    // Don't fail if enqueue fails
    .continueOnJobExecuteFail()    // Continue processing other jobs if this fails
    .rollbackOnJobExecuteFail()    // Rollback any DML if job fails
    .enqueue();
```

## Using Finalizers

Finalizers run after job completion and have access to success/failure context:

```apex
public class MyJobFinalizer extends QueueableJob.Finalizer {
    public override void work() {
        Async.QueueableJobContext ctx = Async.getQueueableJobContext();
        FinalizerContext finalizerCtx = ctx.finalizerCtx;
        
        if (finalizerCtx.getResult() == ParentJobResult.SUCCESS) {
            System.debug('Job completed successfully!');
        } else {
            System.debug('Job failed: ' + finalizerCtx.getException().getMessage());
        }
    }
}

// Attach finalizer within a job
public class MyMainJob extends QueueableJob {
    public override void work() {
        // Do main work...
        
        // Attach finalizer
        Async.queueable(new MyJobFinalizer())
            .attachFinalizer();
    }
}
```

## Configuration

Control job behavior using Custom Metadata (`QueueableJobSetting__mdt`):

1. Go to **Setup → Custom Metadata Types → QueueableJobSetting → Manage Records**
2. Create or edit settings:
   - **All**: Global settings for all jobs
   - **Specific Class Name**: Settings for specific job classes

Available settings:
- **IsDisabled__c**: Disable job execution
- **CreateResult__c**: Create AsyncResult__c records for tracking

## What's Next?

Now that you understand the basics:

1. **Explore the API** - Learn about all available methods and options:
   1. **[Queueable API](/api/queueable.md)** - Detailed information on using Queueable jobs
   2. **[Batchable API](/api/batchable.md)** - Detailed information on using Batchable jobs
   3. **[Schedulable API](/api/schedulable.md)** - Detailed information on using Schedulable jobs
2. **Read the Blog Post** - Check out the detailed explanation: [Apex Queueable Processing Framework](https://blog.beyondthecloud.dev/blog/apex-queueable-processing-framework)
3. **[Initial Scheduled Queueable Batch Job Explanation](/initial-scheduled-queuable-batch-job.md)** - Learn why this job is important for framework to function properly.

## Quick Tips

- **Job Naming**: Jobs get unique names with timestamps: `MyJob::2024-01-15T10:30:45.123Z::1`
- **Custom Job IDs**: Every job gets a UUID for tracking independent of Salesforce Job IDs
- **Priority Matters**: Lower numbers = higher priority. Finalizers always run first.
- **Test Friendly**: Framework handles test context automatically
- **Callouts Supported**: Use `QueueableJob.AllowsCallouts` for HTTP callouts