---
outline: deep
---

# Getting Started

Async Lib is a powerful Salesforce Apex framework that provides an elegant solution for managing asynchronous processes. It eliminates common limitations like "Too many queueable jobs" errors and offers a unified API for queueable, batchable, and schedulable jobs.

## Why Async Lib?

### Key Benefits

- **🚀 Eliminates Queueable Limits**: Automatically handles "Too many queueable jobs" by intelligent chaining and batch overflow
- **🎯 Unified API**: Single, consistent interface for all async job types (Queueable, Batchable, Schedulable)
- **⚡ Smart Prioritization**: Jobs execute based on priority with automatic sorting
- **🛡️ Advanced Error Handling**: Built-in error recovery, rollback options, and continuation strategies
- **📊 Job Tracking**: Comprehensive tracking with custom job IDs and result records
- **⚙️ Configuration-Driven**: Control job behavior through custom metadata without code changes
- **🔗 Powerful Finalizers**: Execute cleanup logic after job completion with full context

## Installation

Deploy to your Salesforce org using the deploy button:

<a href="https://githubsfdeploy.herokuapp.com?owner=beyond-the-cloud-dev&repo=async-lib&ref=main">
  <img alt="Deploy to Salesforce" src="https://raw.githubusercontent.com/afawcett/githubsfdeploy/master/deploy.png">
</a>

Or clone the repository and deploy using SFDX:

```bash
git clone https://github.com/beyond-the-cloud-dev/async-lib.git
cd async-lib
sfdx force:source:deploy -p force-app -u your-org-alias
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

When queueable limits are reached, Async Lib automatically switches to batch-based execution, ensuring your jobs always run without hitting platform limits.

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

1. **[Explore the API](/getting-started)** - Learn about all available methods and options
2. **[See Examples](/getting-started)** - View real-world usage patterns and advanced scenarios
3. **Read the Blog Post** - Check out the detailed explanation: [Apex Queueable Processing Framework](https://blog.beyondthecloud.dev/blog/apex-queueable-processing-framework)

## Quick Tips

- **Job Naming**: Jobs get unique names with timestamps: `MyJob::2024-01-15T10:30:45.123Z::1`
- **Custom Job IDs**: Every job gets a UUID for tracking independent of Salesforce Job IDs
- **Priority Matters**: Lower numbers = higher priority. Finalizers always run first.
- **Test Friendly**: Framework handles test context automatically
- **Callouts Supported**: Use `QueueableJob.AllowsCallouts` for HTTP callouts