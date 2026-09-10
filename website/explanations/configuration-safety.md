---
outline: deep
---

# Configuration Safety

## The rule

> **Mistakes in Apex throw. Mistakes in Custom Metadata degrade and warn.**

Async Lib refuses to enqueue a job that is wrong in code. It never refuses to enqueue a job
because a Custom Metadata record is wrong.

## Why

| | Wrong Apex | Wrong `QueueableJobSetting__mdt` |
| --- | --- | --- |
| Changed by | a developer | an admin |
| Needs a deploy | yes | **no** |
| Runs your tests first | yes | **no** |
| Reaches | the one job just written | **every job in the org**, via the `All` record |

A typo in the `All` record would otherwise stop every async job in production, with no test run
and no deploy to catch it first. Losing a retry costs you a behaviour. Refusing to enqueue stops
the business.

## What happens instead

Each case degrades, records the reason on the job, and writes it to the debug log at `ERROR`.
Nothing is thrown and the job runs.

| Configuration mistake | Result |
| --- | --- |
| `MaxRetries__c` set for a job that declares no reset | retry not applied, job runs once |
| `BackoffStrategy__c` is not a known strategy | no backoff, retries run without delay |
| `MaxRetries__c` above the framework cap | clamped to the cap |
| `LoggerClass__c` cannot be resolved | no logger, jobs run normally |

Every fallback degrades toward doing **less**, never toward doing something the developer did not
ask for. Skipping retry is safe, because the job then runs exactly once, which is what its code
was written and tested against. Silently *enabling* retry on a job that never declared how its
state resets would not be.

Warnings append to the job's retry history, so they reach `AsyncResult__c.RetryHistory__c` when
result creation is enabled. Each one names the record, the job, what was skipped, and the fix.

## What still throws

Anything a developer wrote, because it cannot escape their own test run:

- `retry(n)` or `Async.chunk(...)` without a declared reset, see
  [Job State Between Runs](/explanations/job-state-between-runs)
- `retry(-1)`, or a retry count above the cap passed in Apex
- `delay()` combined with `asyncOptions()`
- `dependsOn(Async.afterPrevious())` with no previous job

These throw at `.enqueue()` or `.chain()`, synchronously, in the caller's transaction.

## Consequence worth knowing

Setting `MaxRetries__c` on the `All` record enables retry only for jobs that have declared how
their state resets. The rest keep running as before and say why in their history.

That is intentional. The alternative is an admin silently enabling state-carrying retries across
an entire org, which is the bug
[Job State Between Runs](/explanations/job-state-between-runs) exists to prevent.
