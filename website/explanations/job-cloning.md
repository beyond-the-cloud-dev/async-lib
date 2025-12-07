---
outline: deep
---

# Job Cloning Explanation

## TL;DR

In Salesforce Apex, everything is passed by value, what mean passing value
itself, or the reference (the memory pointer) to it. Every time you are passing
complex data types, the reference (memory pointer) is shared. When you enqueue a
job using `Async.queueable(this).enqueue()`, you're passing the same instance
that's already in the jobs processing list. Any changes to the job instance
after enqueueing will affect both the original and the queued job, including
critical QueueableJob properties like `isProcessed`.

To prevent this, Async Lib clones every job when adding it to the processing
queue. By default, it uses **soft cloning** (fast but shallow), with an option
for **deep cloning** (slower but complete) when needed.

The difference between soft and deep cloning is demonstrated in the `AsyncTest`
class:

- **[`shouldSoftCloneTheJob`](https://github.com/beyond-the-cloud-dev/async-lib/blob/v2.3.0/force-app/main/default/classes/AsyncTest.cls)**
  method: Shows how primitive properties are properly isolated
- **[`shouldDeepCloneTheJob`](https://github.com/beyond-the-cloud-dev/async-lib/blob/v2.3.0/force-app/main/default/classes/AsyncTest.cls)**
  method: Demonstrates complete object isolation including complex types

View AsyncTest examples for detailed test scenarios.

## Why Do We Need Job Cloning?

### The Problem: Reference Sharing

When you enqueue a queueable job in Apex, you might think you're creating
separate instances:

```apex
public class MyJob extends QueueableJob {
  public String status = 'pending';
  public List<String> processedItems = new List<String>();

  public override void work() {
    this.status = 'processing';
    this.processedItems.add('item1');

    // Enqueue another instance of the same job
    Async.queueable(this).enqueue(); // ❌ PROBLEM!
  }
}
```

**What actually happens:**

- `this` refers to the **same object instance**
- Both the current job and the newly enqueued job share the same memory
  reference
- Changes to properties like `status`, `isProcessed`, or `processedItems` affect
  both jobs
- This can lead to unexpected behavior and corrupted job state

### Real-World Impact

Consider this scenario:

```apex
MyJob job1 = new MyJob();
job1.status = 'initial';

// Enqueue the job
Async.queueable(job1).enqueue();

// Later in the same transaction
job1.status = 'modified'; // This change affects the enqueued job too!
```

**Without cloning:**

- Both the local `job1` variable and the enqueued job point to the same object
- Changing `job1.status` also changes the status of the enqueued job
- Critical framework properties like `isProcessed` can be corrupted

### Framework Internal Impact

Async Lib tracks job state using internal properties:

```apex
public abstract class QueueableJob implements Queueable {
  public Boolean isProcessed = false;
  public Integer priority = 0;
  public String customJobId;
  // ... other tracking properties
}
```

**Without cloning:**

- When a job completes, `isProcessed` gets set to `true`
- If the same instance is in the queue multiple times, all references show
  `isProcessed = true`
- This breaks the framework's job tracking and execution logic

## The Solution: Job Cloning

### How Cloning Works

When you enqueue a job, Async Lib automatically clones it:

```apex
// Your code
Async.queueable(myJob).enqueue();

// What happens internally
QueueableJob clonedJob = myJob.clone(); // Creates a separate instance
// Add clonedJob to the processing queue
```

This ensures that: ✅ Each enqueued job has its own memory space  
✅ Changes to the original don't affect the enqueued job  
✅ Framework properties remain isolated per job instance  
✅ Job execution state is properly maintained

## Types of Cloning

### Soft Clone (Default)

**How it works:** Uses Apex's standard `clone()` method, which performs a
**shallow copy**:

```apex
QueueableJob clonedJob = originalJob.clone();
```

**What gets cloned:**

- ✅ Primitive types: `String`, `Integer`, `Boolean`, `Decimal`, etc.
- ✅ Simple collections of primitives
- ❌ Complex objects (still shared by reference)
- ❌ Nested objects and their properties

**Example:**

```apex
public class MyJob extends QueueableJob {
  public String name = 'test'; // ✅ Cloned
  public Integer count = 5; // ✅ Cloned
  public Account acc = new Account(); // ❌ Shared reference
  public List<Account> accounts; // ❌ Shared reference
}
```

### Deep Clone (Optional)

**How it works:** Uses JSON serialization/deserialization to create a **complete
copy**:

```apex
QueueableJob clonedJob = (QueueableJob) JSON.deserialize(
    JSON.serialize(originalJob),
    QueueableJob.class
);
```

**What gets cloned:**

- ✅ All primitive types
- ✅ All complex objects
- ✅ Nested objects and collections
- ✅ Complete object hierarchy

**When to use:**

```apex
Async.queueable(myJob)
    .deepClone()  // Enable deep cloning
    .enqueue();
```

## Performance Considerations

### Soft Clone Performance

- **Speed**: Very fast (native Apex operation)
- **Memory**: Minimal overhead
- **CPU**: Negligible impact
- **Recommended for**: Most use cases

### Deep Clone Performance

- **Speed**: Slower (JSON serialization overhead)
- **Memory**: Higher overhead (full object duplication)
- **CPU**: More intensive
- **Recommended for**: Jobs with complex object relationships

## Summary

Job cloning is a critical feature that prevents reference corruption in
Salesforce's pass-by-reference environment. Async Lib provides both soft and
deep cloning options, allowing you to balance performance with data integrity
based on your specific needs. The default soft clone handles most scenarios
efficiently, while deep clone is available when complete object isolation is
required.
