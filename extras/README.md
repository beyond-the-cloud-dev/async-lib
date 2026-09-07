# Extras

Classes that are **not** part of the Async Lib package. They belong in your own org, in your own
namespace, which is exactly why they cannot ship inside the package.

Copy what you need. Rename anything to suit your project.

## `BaseQueueableJob`

Only needed when Async Lib is installed as a **namespaced package**. If you deployed the source
directly (Deploy button, `sf project deploy`), skip this, everything already works.

`deepClone()` has to serialize your job, and two Salesforce rules stop Async Lib doing that from
inside its own namespace:

- `JSON.serialize` refuses any object graph containing a type from another namespace
- `Type.forName` cannot resolve your classes when called from package code

Both rules are about **where the code runs**, not which class it belongs to. Running one method
in your namespace satisfies both, which is all this class does.

It mirrors the shape of `btcdev.QueueableJob`, so swap the prefix and carry on:

| Extend | instead of |
| ------ | ---------- |
| `BaseQueueableJob` | `btcdev.QueueableJob` |
| `BaseQueueableJob.AllowsCallouts` | `btcdev.QueueableJob.AllowsCallouts` |
| `BaseQueueableJob.Finalizer` | `btcdev.QueueableJob.Finalizer` |

```apex
public class ImportJob extends BaseQueueableJob {
    public List<Id> recordIds;

    public override void work() {
        // ...
    }
}
```

```apex
public class SyncJob extends BaseQueueableJob.AllowsCallouts {
    public override void work() {
        HttpResponse response = new Http().send(request);
    }
}
```

Every job that extends one of them is covered. There is no per-job override to write and nothing
to remember when you add a new job.

Callout capability survives the clone. The copy is the same concrete class, so it still
implements `Database.AllowsCallouts` and a retried job can still call out. The same holds for
finalizers, which stay recognisable to the framework as `btcdev.QueueableJob.Finalizer`.

### Overriding one job

`cloneForDeepCopy()` is left `virtual` on all three, so a job with unusual needs can still take
over:

```apex
public class OddJob extends BaseQueueableJob {
    public override btcdev.QueueableJob cloneForDeepCopy() {
        // your own copy logic
    }
}
```

See [Deep Clone in Packages](https://async.beyondthecloud.dev/explanations/deep-clone-in-packages)
for the full explanation and for the error messages that point back here.
