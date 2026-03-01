---
outline: deep
---

# Deep Clone in Packages

## TL;DR

When using Async Lib as a **managed or unlocked package** (with the `btcdev` namespace), `.deepClone()` requires you to override `cloneForDeepCopy()` in your `QueueableJob` subclass. Without this override, the framework cannot serialize and deserialize your job across namespace boundaries.

```apex
public class MyJob extends btcdev.QueueableJob {

    public override btcdev.QueueableJob cloneForDeepCopy() {
        return (btcdev.QueueableJob) JSON.deserialize(JSON.serialize(this), MyJob.class);
    }

    public override void work() {
        // your logic
    }
}
```

If you deploy Async Lib **without a namespace** (e.g., via the Deploy button or `sf project deploy`), no override is needed.

## Why Is This Needed?

Deep cloning uses `JSON.serialize()` and `JSON.deserialize()` to create a complete copy of a job instance. Two Salesforce platform behaviors make this fail across namespace boundaries:

### 1. Serialization Context

`JSON.serialize(this)` behaves differently depending on **where** it executes. When called from inside the `btcdev` package code, Salesforce attaches internal platform metadata to `Queueable` implementors that cannot be serialized. The same object serializes fine from subscriber code.

**From package code (fails):**
```apex
// Inside btcdev.QueueableJob.cloneForDeepCopy()
JSON.serialize(this); // System.JSONException: Type cannot be serialized
```

**From subscriber code (works):**
```apex
// Inside your class that extends btcdev.QueueableJob
JSON.serialize(this); // works fine
```

### 2. Type Resolution Context

`Type.forName()` resolves types relative to the **calling code's namespace**. When the package code tries to find your subscriber class, it looks in the `btcdev` namespace where your class doesn't exist.

**From package code:**
```apex
// Inside btcdev.QueueableJob
Type.forName('MyJob'); // returns null (looks for btcdev.MyJob)
```

**From subscriber code:**
```apex
// Inside your class
Type.forName('MyJob'); // returns MyJob.class
```

## The Solution

The `cloneForDeepCopy()` method is `virtual`, allowing you to override it in your subclass. Your override runs in your namespace context, where both serialization and type resolution work correctly.

```apex
public class AccountProcessorJob extends btcdev.QueueableJob {
    public List<Account> accounts;
    public Map<String, Object> config;

    public override btcdev.QueueableJob cloneForDeepCopy() {
        return (btcdev.QueueableJob) JSON.deserialize(
            JSON.serialize(this), AccountProcessorJob.class
        );
    }

    public override void work() {
        // process accounts
    }
}
```

Then use `.deepClone()` as normal:

```apex
btcdev.Async.queueable(new AccountProcessorJob())
    .deepClone()
    .enqueue();
```

## When Do I Need This?

| Scenario | Override needed? |
|----------|:---:|
| Deployed without namespace (Deploy button / `sf deploy`) | No |
| Installed as package, using `.deepClone()` | **Yes** |
| Installed as package, NOT using `.deepClone()` | No |

## Error Message

If you forget the override, the framework throws a descriptive error:

```
deepClone() failed for the job "MyJob".
When using a namespaced package, override cloneForDeepCopy() in your QueueableJob subclass:
public override QueueableJob cloneForDeepCopy() {
    return (QueueableJob) JSON.deserialize(JSON.serialize(this), YourClassName.class);
}
```

## Soft Clone vs Deep Clone Recap

Not sure if you need `.deepClone()` at all? See [Job Cloning](/explanations/job-cloning) for when soft clone (default) is sufficient vs when deep clone is required.
