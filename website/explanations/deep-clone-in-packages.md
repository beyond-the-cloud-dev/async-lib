---
outline: deep
---

# Deep Clone in Packages

## TL;DR

When Async Lib is installed as a **namespaced package** (`btcdev`), `.deepClone()` needs one
line of help from your namespace. Write this base class **once** and extend it instead of
`btcdev.QueueableJob`:

```apex
public abstract class BaseQueueableJob extends btcdev.QueueableJob {
    public static btcdev.QueueableJob deepCopy(btcdev.QueueableJob job) {
        return (btcdev.QueueableJob) JSON.deserialize(
            JSON.serialize(job),
            Type.forName(job.className)
        );
    }

    public virtual override btcdev.QueueableJob cloneForDeepCopy() {
        return deepCopy(this);
    }

    public abstract class AllowsCallouts extends btcdev.QueueableJob.AllowsCallouts {
        public virtual override btcdev.QueueableJob cloneForDeepCopy() {
            return BaseQueueableJob.deepCopy(this);
        }
    }

    public abstract class Finalizer extends btcdev.QueueableJob.Finalizer {
        public virtual override btcdev.QueueableJob cloneForDeepCopy() {
            return BaseQueueableJob.deepCopy(this);
        }
    }
}
```

It mirrors the shape of `btcdev.QueueableJob`, so swap the prefix and carry on:

| Extend | instead of |
| ------ | ---------- |
| `BaseQueueableJob` | `btcdev.QueueableJob` |
| `BaseQueueableJob.AllowsCallouts` | `btcdev.QueueableJob.AllowsCallouts` |
| `BaseQueueableJob.Finalizer` | `btcdev.QueueableJob.Finalizer` |

```apex
public class MyJob extends BaseQueueableJob {
    public override void work() {
        // your logic
    }
}
```

Every job that extends one of them is covered. There is no per-job override to write and nothing
to remember when you add a new job.

Callout capability survives the clone. The copy is the same concrete class, so it still
implements `Database.AllowsCallouts` and a retried job can still call out. Finalizers stay
recognisable to the framework as `btcdev.QueueableJob.Finalizer`.

The file is in
[`extras/classes/BaseQueueableJob.cls`](https://github.com/beyond-the-cloud-dev/async-lib/blob/main/extras/classes/BaseQueueableJob.cls),
ready to copy. Rename it to suit your project.

If you deploy Async Lib **without a namespace** (Deploy button, `sf project deploy`), skip all of
this. Everything already works.

## Per-Job Override

`cloneForDeepCopy()` on the base class is left `virtual`, so a job with unusual needs can still
take over:

```apex
public class OddJob extends BaseQueueableJob {
    public override btcdev.QueueableJob cloneForDeepCopy() {
        // your own copy logic
    }
}
```

You can also skip the base class entirely and override per job, naming the type explicitly:

```apex
public class MyJob extends btcdev.QueueableJob {
    public override btcdev.QueueableJob cloneForDeepCopy() {
        return (btcdev.QueueableJob) JSON.deserialize(JSON.serialize(this), MyJob.class);
    }
}
```

That is the older approach. It works, but you pay for it on every job.

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

## Why One Base Class Is Enough

`cloneForDeepCopy()` is `virtual`, so you can override it anywhere in the hierarchy. Both
platform rules above are about **where the code runs**, not which class it belongs to. Put the
override on a base class in your namespace and every subclass inherits a working deep clone,
because the serialization and the `Type.forName` both happen in your namespace.

`Type.forName(this.className)` is what removes the per-job part. `className` already holds the
runtime class name, so the base class resolves whichever subclass it was called on.

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

## Error Messages

A failed deep clone always names the cause first, then what to do about it. Forgetting
the override in a packaged org looks like this:

```
deepClone() failed for the job "MyJob": System.JSONException: Type cannot be serialized
Async Lib is installed as a namespaced package, so it cannot serialize your class.
Override cloneForDeepCopy() in your QueueableJob subclass: public override
QueueableJob cloneForDeepCopy() { return (QueueableJob)
JSON.deserialize(JSON.serialize(this), YourClassName.class); }
```

The namespace is not the only thing that can stop a deep clone, and the message tells
you which one you hit:

| Cause | Fix |
| ----- | --- |
| `Type cannot be serialized` | You are on a packaged install without the override above |
| `Cycle detected` | The job holds a reference back to itself. Break the cycle, or mark the field `transient` |
| `Cannot deserialize JSON as abstract type` | A field is typed as an interface or abstract class, which JSON cannot rebuild. Mark it `transient`, or hold a concrete type |

## Size Limits

A deep clone holds the original and the copy at the same time, so it costs roughly
twice the job's size in heap. Measured, a 1 MB job needs about 2 MB. With a 6 MB
synchronous heap that puts the practical ceiling at roughly **2 MB of job state**, or
about 4 MB from an asynchronous caller where the limit is 12 MB.

There is no separate cap on the serialized job itself: a 5 MB job enqueues and runs
fine. The caller's heap is what runs out first.

## Soft Clone vs Deep Clone Recap

Not sure if you need `.deepClone()` at all? See [Job Cloning](/explanations/job-cloning) for when soft clone (default) is sufficient vs when deep clone is required.
