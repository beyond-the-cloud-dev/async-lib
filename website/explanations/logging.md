---
outline: deep
---

# Logging

## TL;DR

Register one class, and every async job in the org reports to it.

```apex
global class AsyncJobLogger implements Async.OnJobFailed {
    public void onJobFailed(Async.FailureContext ctx) {
        Logger.error('Async job failed: ' + ctx.className, ctx.failure.message);
        Logger.saveLog();
    }
}
```

Then set `LoggerClass__c` to `AsyncJobLogger` on the `All` record of
`QueueableJobSetting__mdt`. That is the whole setup.

::: warning The class must be `global`

Async Lib resolves your class by name from inside its own namespace, and `Type.forName` only
reaches a subscriber class declared `global`. A `public` class resolves to null and nothing is
logged.

Only the **class** needs `global`. The methods stay `public`.

Declare it `global` even when you deploy the source rather than installing the package. It is
harmless there, and it means the same class keeps working if you ever switch.

:::

## Events

Implement only the ones you want. Each is a separate interface, so a logger that only cares about
failures implements one method and nothing else.

| Interface | Fires | Context |
| --------- | ----- | ------- |
| `Async.OnJobEnqueued` | a job is added to a chain | `JobContext` |
| `Async.OnJobSucceeded` | a job finished without failing | `JobContext` |
| `Async.OnJobFailed` | a job failed with no attempts left | `FailureContext` |
| `Async.OnRetryEnqueued` | an attempt failed and another is queued | `FailureContext` |

A job that fails with `retry(2)` and never succeeds produces `OnRetryEnqueued`, `OnRetryEnqueued`,
`OnJobFailed`. Every failed attempt fires exactly one event, so the two together tell you whether
to warn or to page. There is no overlap and no double counting.

Chunk runs fire `OnJobEnqueued` per page, because each page really is queued separately.

## Two layers, one vocabulary

The same interfaces work on a **job**, with no Custom Metadata at all:

```apex
public class ImportJob extends QueueableJob implements Async.OnJobFailed {
    public override void work() { ... }

    public void onJobFailed(Async.FailureContext ctx) {
        // just this job
    }
}
```

Both fire for the same event, and the job's own listener runs first. Use the job listener for
one-off behaviour and the registered class for the org-wide sink. Neither needs the other.

## Attaching your own metadata

`info(...)` puts arbitrary key/value pairs on a job, and they arrive on every context. This is how
you route alerts by team, package or anything else you own:

```apex
Async.queueable(new ImportJob())
    .info('team', 'platform')
    .info('package', 'billing')
    .enqueue();
```

```apex
public void onJobFailed(Async.FailureContext ctx) {
    String team = ctx.info.get('team');
}
```

It survives serialization, retries and chunk pages, because it travels on the job.

## Per-job override

`LoggerClass__c` resolves job-first, then falls back to the `All` record, the same way retry
settings do:

| Record | `LoggerClass__c` | Result |
| ------ | ---------------- | ------ |
| `All` | `AsyncJobLogger` | every job goes here |
| `ImportJob` | `ImportJobLogger` | that job goes here instead |
| `ImportJob` | blank | that job falls back to `All` |

## A logger that throws cannot break a job

Every listener call is wrapped. If yours throws, the failure is written to the debug log and the
job carries on untouched. By the time most events fire the job has already done its work, so
failing it over a logging problem would turn an observability problem into a data problem.

The same applies to a `LoggerClass__c` that cannot be resolved: jobs keep running, and the reason
is recorded. See [Configuration Safety](/explanations/configuration-safety).

## Testing your logger

Custom Metadata cannot be inserted in Apex, so register the logger through
`AsyncMock` instead. This is the only way to assert that the framework actually routes to you:

```apex
@IsTest
static void shouldLogFailures() {
    AsyncMock.jobSettings(
        new List<QueueableJobSetting__mdt>{
            new QueueableJobSetting__mdt(
                QueueableJobName__c = 'All',
                LoggerClass__c = 'MyAsyncLogger'
            )
        }
    );

    Test.startTest();
    Async.queueable(new FailingJob()).continueOnJobExecuteFail().enqueue();
    Test.stopTest();

    // assert on whatever MyAsyncLogger recorded
}
```

The same call covers every other Custom Metadata driven behaviour: retry defaults, backoff,
retryable exceptions, result creation and disabled jobs. See
[AsyncMock.jobSettings](/api/async-mock#jobsettings).

## Nebula Logger adapter

```apex
global class NebulaAsyncLogger implements Async.OnJobFailed, Async.OnRetryEnqueued {
    public void onJobFailed(Async.FailureContext ctx) {
        Logger.error(
            String.format(
                'Async job {0} failed after {1} attempt(s): {2}',
                new List<String>{
                    ctx.className,
                    String.valueOf(ctx.retryAttempt + 1),
                    ctx.failure?.message
                }
            )
        );
        Logger.setScenario(ctx.info.get('team'));
        Logger.saveLog();
    }

    public void onRetryEnqueued(Async.FailureContext ctx) {
        Logger.warn(
            'Async job ' +
                ctx.className +
                ' attempt ' +
                ctx.retryAttempt +
                ' failed, retrying in ' +
                ctx.nextAttemptDelayMinutes +
                'm'
        );
        Logger.saveLog();
    }
}
```

`saveLog()` is called inside the listener on purpose. Each Queueable execution is its own
transaction, so there is no later point at which to flush.

## Scope

Queueable only, including chunk runs. Batchable and Schedulable do not fire these events yet,
because the framework does not own their base classes.

`AsyncResult__c` is untouched and orthogonal. Use either, both, or neither.
