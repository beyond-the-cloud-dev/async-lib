---
# https://vitepress.dev/reference/default-theme-home-page
layout: home

hero:
  name: "Async Lib"
  text: "Async Apex you can actually monitor"
  tagline: 'The Salesforce library for Queueable, Batch and Schedule behind one API. No more "Too many queueable jobs". Failures retry or get requeued, and every linked chain shows live on its record.'
  actions:
    - theme: brand
      text: Get Started
      link: /getting-started
    - theme: alt
      text: See the Job Timeline
      link: /features/job-timeline

features:
  - title: Job Timeline on the Record
    details: Every chain linked to a record, live on its record page. Steps, chunk progress, failures, what added what, and a map of what depends on what.
    link: /features/job-timeline
  - title: Requeue Failed Work
    details: Run failed steps again from the record page, in order, with their dependencies. Failed batch scopes go again through the batch's own execute().
    link: /features/requeue
  - title: Smart Queueable Jobs
    details: Automatically handles "Too many queueable jobs" errors through intelligent chaining and batch overflow. Features priority-based execution, sophisticated error handling, and powerful finalizers for cleanup logic.
    link: /api/queueable
  - title: Chunked Processing
    details: Hand a chunk run a list, a set of ids, or a SOQL cursor and it pages through them across chained Queueables. Per-page tracking, retry and backoff, and the run takes one slot in the chain so later jobs wait for it.
    link: /api/chunk
  - title: Unified Batch Processing  
    details: Execute batch jobs immediately or schedule them for later with configurable scope sizes. Convert any batch job to schedulable with a single method call. Built-in error handling and result tracking.
    link: /api/batchable
  - title: Flexible Scheduling
    details: Intuitive CronBuilder for complex scheduling patterns. Convert queueable or batch jobs to schedulable effortlessly. Support for business hours, recurring intervals, and custom cron expressions.
    link: /api/schedulable
---

<div class="landing-section">

## See it, then fix it

**Watch a chain run.** Jobs, chunk pages and retries update in place, and a job added at runtime shows up where it will run.

![A running chain on the record page, with a chunk run and a live progress bar](/images/job-timeline/running.png)

**Find out what broke and why.** The failed step opens with its exception, and the steps it took down with it are marked as skipped. Requeue them in one click.

![A failed chain with its exception and the requeue button](/images/job-timeline/failed-chain.png)

**See what depends on what.** The chain map draws the run order and every dependency, met or not.

![The chain map with dependency lines between jobs](/images/job-timeline/chain-map.png)

</div>

<div class="landing-section">

## Less code than doing it by hand

Your job logic stays the same. Async Lib takes over enqueueing, chaining and tracking.

::: code-group

```apex [Async Lib]
public class SyncAccountsJob extends QueueableJob {
    public override void work() {
        // your logic
    }
}

Async.queueable(new SyncAccountsJob())
    .linkRecord(account.Id)
    .chain(new NotifyOwnersJob())
    .enqueue();
```

```apex [Standard Apex]
public class SyncAccountsJob implements Queueable {
    public void execute(QueueableContext context) {
        // your logic
        System.enqueueJob(new NotifyOwnersJob());
        // one child per Queueable: a second enqueue here throws
        // "Too many queueable jobs". Nothing records what ran.
    }
}

System.enqueueJob(new SyncAccountsJob());
```

:::

[Every pattern side by side](/introduction/standard-apex-vs-async-lib) or [install it](/getting-started).

</div>
