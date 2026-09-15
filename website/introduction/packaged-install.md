---
outline: deep
---

# Installing as a Package

## TL;DR

Everything a **packaged** install needs that a source deploy does not, on one page. If you
[deployed the source](/introduction/source-deploy) instead, skip this: there is no namespace
boundary and everything already works.

Most of the library needs nothing beyond the `btcdev.` prefix. A few features copy or store your
job, and those need one class from [`extras/`](https://github.com/beyond-the-cloud-dev/async-lib/tree/main/extras/classes)
in your namespace. That is the whole story, and the rest of this page is the details.

## The one rule behind all of it

Async Lib runs inside its own `btcdev` namespace, and two platform behaviours follow from that:

| Rule | Consequence |
| ---- | ----------- |
| `JSON.serialize` and `JSON.deserialize` refuse any object graph that crosses a namespace, in either direction | anything that copies or stores your job has to run in **your** code |
| `Type.forName` from package code only resolves a subscriber class declared `global` | anything Async Lib reaches **by name** has to be `global` |

Every item below is a consequence of one of those two. Neither depends on whether your job class
is `public` or `global`; `global` gets a class past `Type.forName` and buys nothing else.

## Checklist

### 1. Install

The current version and install link are on [Installation](/introduction/installation).

### 2. Use the prefix

Every class, object and field carries it.

| Source deploy | Packaged install |
| ------------- | ---------------- |
| `Async.queueable(...)` | `btcdev.Async.queueable(...)` |
| `extends QueueableJob` | `extends btcdev.QueueableJob` |
| `implements Async.Retryable` | `implements btcdev.Async.Retryable` |
| `AsyncResult__c` | `btcdev__AsyncResult__c` |
| `QueueableJobSetting__mdt.CreateResult__c` | `btcdev__QueueableJobSetting__mdt.btcdev__CreateResult__c` |

The framework's error messages use the right prefix for the org they run in, so whatever a message
tells you to write can be pasted as is.

### 3. Copy the `extras` classes you need

The classes in
[`extras/classes/`](https://github.com/beyond-the-cloud-dev/async-lib/tree/main/extras/classes)
belong in your namespace, which is exactly why they cannot ship inside the package. Copy the ones
for the features you use and rename them however you like.

| Copy | When you use | Then |
| ---- | ------------ | ---- |
| `BaseQueueableJob` | `deepClone()`, `restoreStateOnRetry()` | `extends BaseQueueableJob` instead of `btcdev.QueueableJob` |
| `BaseQueueableJob.Finalizer` | the same, on a finalizer | `extends BaseQueueableJob.Finalizer` |
| `BaseChunkJob` | `restoreStateOnNextChunk()` | `extends BaseChunkJob` instead of `btcdev.ChunkJob` |
| `AsyncJobSerializer` | `Async.requeue()` | register it, see step 4 |

Callouts are a marker, not a base class, so `implements Database.AllowsCallouts` works on any of
them. Why the base classes exist is in
[Deep Clone in Packages](/explanations/deep-clone-in-packages), and the serializer in
[Requeue](/explanations/requeue).

### 4. Declare `global` on anything you register by name

Two fields on `QueueableJobSetting__mdt` name a class for Async Lib to construct. Both classes
must be `global`, or the name resolves to nothing. Only the class needs it, the methods stay
`public`.

| Field | Implements | Ships in `extras`? |
| ----- | ---------- | ------------------ |
| `LoggerClass__c` | one or more of `btcdev.Async.OnJobEnqueued`, `OnJobSucceeded`, `OnJobFailed`, `OnRetryEnqueued` | no, that one is yours to write |
| `JobSerializerClass__c` | `btcdev.Async.JobSerializer` | yes, `AsyncJobSerializer` |

A name that does not resolve degrades rather than throws: no logging, or `NotSerializable` on the
result, plus a warning in `RetryHistory__c` naming the field. It never stops a job. See
[Configuration Safety](/explanations/configuration-safety).

### 5. Assign the permission set

`btcdev__AsyncResultAccess` grants read on `btcdev__AsyncResult__c` and every field on it, for
admins and reports. The framework writes those records in system context and does not need it
itself.

`JobPayload__c` is part of that set. If you turn `StoreJobPayload__c` on, whoever holds the set can
read whatever data your jobs carried, so review it first.

## Feature by feature

What each feature needs on a packaged install, and nothing more.

| Feature | Needs |
| ------- | ----- |
| enqueue, chain, finalizers, `retry(n)`, `backoff`, `dependsOn` | the prefix |
| `Async.Retryable`, `Async.ChunkResettable` | the prefix |
| `deepClone()`, `restoreStateOnRetry()` | `BaseQueueableJob` |
| `restoreStateOnNextChunk()` | `BaseChunkJob` |
| `LoggerClass__c` | your logger class, declared `global` |
| `Async.requeue()` | `AsyncJobSerializer`, copied and registered |

## Writing tests against the package

`btcdev.AsyncMock` is part of the package and callable from your tests, so none of the settings
above need real Custom Metadata:

```apex
btcdev.AsyncMock.jobSettings(
    new List<btcdev__QueueableJobSetting__mdt>{
        new btcdev__QueueableJobSetting__mdt(
            btcdev__QueueableJobName__c = 'All',
            btcdev__LoggerClass__c = 'MyAsyncLogger',
            btcdev__StoreJobPayload__c = 'Yes',
            btcdev__JobSerializerClass__c = 'AsyncJobSerializer'
        )
    }
);
```

The prefixed constructor also works in a source deploy, so a test written this way does not need
to change if you ever switch.

## Error messages that point back here

| Message | You skipped |
| ------- | ----------- |
| `deepClone() failed ... Type cannot be serialized` | step 3, `BaseQueueableJob` |
| `LoggerClass__c names "X", which could not be resolved` | step 4, `global` on the logger |
| `StoreJobPayload__c is Yes for "X", but the job could not be serialized` | steps 3 and 4, `AsyncJobSerializer` |
| `JobSerializerClass__c names "X", which is not a usable btcdev.Async.JobSerializer` | step 4, `global` or the interface |
