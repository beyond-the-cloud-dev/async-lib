---
outline: deep
---

# Initial Scheduled Queueable Batch Job Explanation

## TL;DR

Due to the fact that we cannot:

- determine if current enqueued queueable job is the last one in the Apex transaction,
- pass QueueableChain job as reference to `System.enqueueJob()`, and later in Apex transaction add new jobs to this chain,
- abort queueable job and preserve the Queueable Job limits (running `System.enqueueJob()` and later `System.abortJob()` doesn't revert the Queueable Job limits),

The only option is to *somehow* enqueue a queueable chain, and in case of next `System.enqueueJob()` call, abort that job and enqueue a new one with additional job.

This *somehow* approach, is exactly what the initial scheduled queueable batch job implementation does.

## Why Do We Need QueueableChainBatch?

### The Challenge: Queueable Job Limits

Salesforce has strict limits on queueable jobs:
- **Maximum 50 queueable jobs** can be enqueued per transaction
- Once you hit this limit, `System.enqueueJob()` will throw an exception
- Using `System.abortJob()` does not free up the queueable job limits
- This creates a problem when you need to process more than 50 jobs efficiently

### The Goal: Efficient Job Processing

To be efficient, Async Lib tries to enqueue as many queueable jobs as possible in the synchronous context. This means:
1. Enqueue jobs normally using `System.enqueueJob()` (jobs 1-50)
2. Once reaching 50 queueable jobs, switch to an alternative approach for the remaining jobs
3. Schedule `QueueableChainBatch` to handle jobs beyond the 50-job limit

### The Technical Problem

The core issue is **we don't know how many more jobs will be enqueued** during the current transaction:

```apex
// We're at 49 jobs enqueued
Async.queueable(new Job50()).enqueue(); // This works fine

// But what happens next?
Async.queueable(new Job51()).enqueue(); // We need to handle this!
Async.queueable(new Job52()).enqueue(); // And this!
Async.queueable(new Job53()).enqueue(); // And this...?
// ... potentially many more jobs
Async.queueable(new JobXXXXX()).enqueue(); // How many more...?
```

**Why we can't just enqueue the chain at job #50:**
- `System.enqueueJob()` only passes the **current state** of the job
- If we enqueue a `QueueableJob` with chain details as the 50th job
- And later try to add job #51 to that chain
- **It won't work** because the chain was already enqueued and is immutable

### Failed Approach: Enqueue + Abort

A logical solution might be:
1. Enqueue a job with the current chain state
2. If more jobs come in, abort the previous job and enqueue a new one with updated chain

**However, this doesn't work because:**
- Using `System.enqueueJob()` followed by `System.abortJob()` in the same transaction
- **Still consumes the queueable job limits**
- The limits are not restored when you abort
- This means you quickly run out of limit slots

### The Solution: Scheduled Batch Jobs

**Database.executeBatch() has different behavior:**
- Batch jobs are **not tied to the same queueable job limits**
- When using `System.abortJob()` on a batch job, **the limits are properly restored**
- This allows us to execute, abort, and re-execute as many times as needed

**How the QueueableChainBatch works:**
1. When we hit the queueable limit, schedule a batch job with the current chain state
2. If more jobs are added during the transaction:
   - Abort the previous batch job
   - Schedule a new batch job with the updated chain (including new jobs)
3. Repeat as needed until the transaction ends
4. The final batch job executes with all the accumulated jobs

### Why Scheduled Instead of Immediate Batch?

Initially, we tried executing batch jobs immediately, but we encountered another Salesforce limitation:

**Batch Job Execution Limits:**
- There is no option to execute batch jobs from `start()` and `execute()` methods (Full Error Message: "Database.executeBatch cannot be called from a batch start, batch execute, or future method")
- There is a limit of enqueueing only one Queueable job in a batch context.
- This means in a batch context, in case of more than one queueable job being enqueued, initial batch job will fail to execute.

**The Scheduled Solution:**
- Instead of executing the batch immediately, we **schedule it to run 1 minute in the future**
- This bypasses the batch-from-batch execution limits
- The scheduled job runs in a clean context without the restrictions
- This approach handles all edge cases reliably

## Real-World Example

Here's what happens when you enqueue 75 jobs:

```apex
// In your code
for (Integer i = 1; i <= 75; i++) {
    Async.queueable(new ProcessingJob(i)).enqueue();
}
```

**Behind the scenes:**
1. **Jobs 1-50**: Enqueued normally using `System.enqueueJob()`
2. **Job 51**: Triggers QueueableChainBatch creation, scheduled for +1 minute
3. **Jobs 52-75**: Each addition aborts previous batch and schedules new one with updated chain
4. **Final result**: One scheduled batch job containing jobs 51-75 in the chain

## Benefits of This Approach

✅ **No Limit Errors**: Never throws "Too many queueable jobs" exceptions  
✅ **Efficient Processing**: Uses direct queueable jobs when possible  
✅ **Automatic Fallback**: Seamlessly switches to batch processing when needed  
✅ **Complete Chain Execution**: All jobs execute in the correct order  
✅ **Error Recovery**: Handles various Salesforce governor limit scenarios  



