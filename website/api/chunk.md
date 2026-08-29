# Chunk API

Apex classes `ChunkBuilder.cls`, `ChunkJob.cls`, and `ChunkSource.cls`.

Process a large data set in tuned pages across chained Queueables, with the same
per-job tracking and retry/backoff as a normal `QueueableJob`. Reach for this when
you need to process thousands of records in the background but do not want a
`Database.Batchable` (heavier, separate lifecycle) or one job per record.

Each page runs as its own tracked job in the chain. When a page settles, the
framework appends the next page and drops the settled one, so only the current
position moves forward and a huge run never materializes a giant job list.

A chunk run is an ordinary chain member. Jobs chained before it run first, jobs
chained after it wait for the last page, and `dependsOn(...)` resolves against the
outcome of the whole run. See [Placing a run in a chain](#placing-a-run-in-a-chain).

**Common ChunkJob class example:**

Extend `ChunkJob` and put your per-page logic in `work(List<SObject> chunk)`.

```apex
public class AccountRecalcJob extends ChunkJob {
  public override void work(List<SObject> chunk) {
    List<Account> accounts = (List<Account>) chunk;
    for (Account acc : accounts) {
      acc.Description = 'Recalculated';
    }
    update accounts;
  }
}
```

```apex
Async.Result result = Async.chunk(new AccountRecalcJob(), ChunkSource.of(records))
	.chunkSize(50)
	.priority(5)
	.retry(2)
	.enqueue();
```

::: warning deepClone is not supported for a ChunkJob
Pages share one source and are isolated by serialization at each enqueue, and a
`Database.Cursor` source cannot be JSON-serialized. `Async.chunk(...)` throws if
the job has `deepClone` set. Build the job fully before handing it to
`Async.chunk(...)` (do not mutate its members afterward).
:::

**Carrying state between chunks:**

Your job keeps its own members for the length of the run. A page starts from the
state the previous page left behind, so a running total or a map built on one page
is still there on the next one. This is what `Database.Stateful` gives a batch,
without asking for it.

```apex
public class RevenueRollupJob extends ChunkJob {
  private Map<Id, Decimal> revenueByOwner = new Map<Id, Decimal>();
  private Integer processed = 0;

  public override void work(List<SObject> chunk) {
    for (Opportunity opp : (List<Opportunity>) chunk) {
      Decimal current = revenueByOwner.get(opp.OwnerId);
      revenueByOwner.put(opp.OwnerId, (current == null ? 0 : current) + opp.Amount);
    }
    processed += chunk.size();
  }
}
```

Keep those members serializable and small: they travel with the job on every hop.
A page that fails and retries starts from the state that attempt began with, so
keep the accumulation idempotent if you retry.

**Working by id:**

When the work only needs ids, feed the run `ChunkSource.ofIds(...)` and read them
straight off the page. Ids are 18 characters each, so they travel far more cheaply
across hops than whole records, and re-querying inside `work(...)` means a long run
acts on current data rather than a snapshot taken before the first page.

```apex
public class CreateWelcomeTasksJob extends ChunkJob {
  public override void work(List<SObject> chunk) {
    List<Task> tasks = new List<Task>();
    for (Id accountId : new Map<Id, SObject>(chunk).keySet()) {
      tasks.add(new Task(WhatId = accountId, Subject = 'Welcome call'));
    }
    insert tasks;
  }
}
```

```apex
Async.chunk(new CreateWelcomeTasksJob(), ChunkSource.ofIds(accountIds))
	.chunkSize(200)
	.enqueue();
```

`ofIds` yields id-only shells, so there are no other fields to read. If your job
needs fields, query them inside `work(...)` or use a source that selects them.

**Large set via SOQL cursor example:**

For sets too large to hold in memory, hand the framework a `Database.Cursor` (or a
SOQL string it opens for you). The cursor is never fully materialized; each page
fetches its slice.

```apex
Async.chunk(new AccountRecalcJob(), ChunkSource.query('SELECT Id FROM Account WHERE ...'))
	.chunkSize(200)
	.enqueue();
```

## Placing a run in a chain

The run holds one slot in the chain. Every page of it finishes before the next
chain member starts, however many pages the source yields.

```apex
Async.queueable(new PrepareJob())
	.chunk(new AccountRecalcJob(), ChunkSource.query('SELECT Id FROM Account WHERE ...'))
	.chunkSize(200)
	.chain(new NotifyJob())
	.dependsOn(Async.afterPrevious().succeeded())
	.enqueue();
```

`PrepareJob` runs, then every page of the run, then `NotifyJob`.

Runs chain to each other the same way, for multi-stage pipelines:

```apex
Async.chunk(new StageOneJob(), firstSource)
	.chunkSize(200)
	.chunk(new StageTwoJob(), secondSource)
	.chunkSize(100)
	.enqueue();
```

`dependsOn(...)` against a chunk run reads the outcome of the run as a whole:

| Required outcome | Runs when                              |
| ---------------- | -------------------------------------- |
| `.succeeded()`   | every page finished without failing    |
| `.failed()`      | at least one page failed               |
| `.finished()`    | the run ended, whatever the outcome    |

Priority still decides who goes first. A job added while the run is in flight with
a higher priority runs before the next page, then the run resumes. A job of equal
or lower priority (or no priority at all) waits for the whole run.

```apex
public class AccountRecalcJob extends ChunkJob {
  public override void work(List<SObject> chunk) {
    // ...
    Async.queueable(new UrgentJob()).priority(1).chain(); // jumps the remaining pages
  }
}
```

## Failure handling

Two independent levels:

- **Per chunk (retry).** A page that throws retries per `.retry(...)` /
  `.backoff(...)`, exactly like a `QueueableJob`. Each terminal page records an
  `AsyncResult__c` row (`COMPLETED` or `FAILED`).
- **Across the run.** By default the run keeps processing the remaining chunks
  even if one fails (best-effort, `Batchable`-like). Call
  `.stopRemainingChunksOnFailure()` to stop the run when a chunk exhausts its
  retries.

A run that ends early records one summary `AsyncResult__c` naming the page it
stopped at and how much work was left, so you can tell a completed run from a
truncated one:

| Ended by                          | Status                  |
| --------------------------------- | ----------------------- |
| `.stopRemainingChunksOnFailure()` | `SKIPPED_CHUNK_STOPPED` |
| `Async.stopChain()`               | `SKIPPED_CHAIN_STOPPED` |

`Async.stopChain()` stops the whole chain wherever it is, including mid-run.

## Cursor governor caps

`ChunkSource.cursor(...)` / `ChunkSource.query(...)` open a SOQL cursor. Salesforce
enforces cursor limits you should weigh against a `Database.Batchable`:

| Limit                              | Value                        |
| ---------------------------------- | ---------------------------- |
| Rows per cursor                    | 50 million                   |
| Records per `fetch()` call         | 2,000 (caps `chunkSize` on a cursor source) |
| `fetch()` calls per transaction    | 100 (a page uses one)        |
| Cursor instances per org per day   | 10,000                       |
| Cursor lifespan                    | 2 days                       |

::: warning A throttled run can outlive its cursor
A cursor expires 2 days after it is opened. A run that pages a large set with
`.delayBetweenChunks(...)`, or one that sits behind a long queue, can still have
pages left when the cursor dies. Size `chunkSize` and the delay so the run
finishes inside 2 days, or use a `Database.Batchable` for very long runs.
:::

`ChunkSource.of(...)` / `ChunkSource.ofIds(...)` hold records in memory instead, so
they are bounded by heap, not cursor limits. Prefer them for smaller sets and for
tests.

## Security

`ChunkSource.query(String soql)` runs the SOQL you pass, so you own its safety.
Use a bind overload rather than concatenating user input. The framework hands each
page to your `work(...)` as queried; it does not strip fields.

```apex
ChunkSource.query(
  'SELECT Id FROM Account WHERE Industry = :industry',
  new Map<String, Object>{ 'industry' => userInput }
);
```

### Access level

**A cursor opened by `ChunkSource` runs in `AccessLevel.SYSTEM_MODE` by default.**
Field-level security, object permissions and sharing rules are not applied. Chunk
runs are usually administrative work over data the running user may not personally
see, so this matches both `Database.getCursor` on the current API version and what
most runs actually want. It is still a deliberate choice you should be aware of.

Pass an `AccessLevel` to change it:

```apex
ChunkSource.query('SELECT Id FROM Account WHERE ...', AccessLevel.USER_MODE);

ChunkSource.query(
  'SELECT Id FROM Account WHERE Industry = :industry',
  new Map<String, Object>{ 'industry' => userInput },
  AccessLevel.USER_MODE
);
```

`WITH USER_MODE` inside the query string works too and wins over the parameter.

::: warning Why this is passed explicitly

The framework always passes an `AccessLevel` rather than relying on the platform
default, because that default is not stable. Per the Apex Developer Guide, "in API
version 67.0 and later, Apex runs in user context by default", where API 66.0 and
earlier default to system mode.

Had `ChunkSource` relied on the implicit default, bumping the API version would
have silently switched every existing run to user mode, and runs would quietly
return fewer rows with no error. Passing it explicitly keeps behaviour identical
across that bump.

:::

## Testing a run

A chunk page is an ordinary job in the chain, so everything in
[AsyncMock](/api/async-mock) works on a run exactly as it does on a queueable.
What a chunk run adds is the **source**, and that needs no mock: you pass it to
`Async.chunk(...)` yourself, so a test swaps it at the call site.

| To test                        | Do this                                               |
| ------------------------------ | ----------------------------------------------------- |
| Your `work(...)` logic         | Call `work(records)` directly. No enqueue, no chain.   |
| Paging, state, failure policy  | `ChunkSource.of(records)` in place of the real source  |
| Your SOQL string               | Insert data and use the real `ChunkSource.query(...)`  |
| Paging at scale, broken fetch  | Your own `ChunkSource` subclass                        |
| A page's `QueueableContext`    | `.mockId(...)` plus `AsyncMock.whenQueueable(...)`     |
| A specific page failing        | `.mockId(...)` plus `AsyncMock.whenQueueable(...).thenThrow(...)` |
| A page finalizer's error path  | `.mockId(...)` on the finalizer plus `AsyncMock.whenFinalizer(...).thenThrow(...)` |

Every page consumes one entry from the mock queue, so mixing `thenReturn` and
`thenThrow` picks which page fails:

```apex
AsyncMock.whenQueueable('recalc-run')
	.thenReturn(new AsyncMock.MockQueueableContext())   // page 1 succeeds
	.thenThrow(new CalloutException('boom'))            // page 2 fails
	.thenReturn(new AsyncMock.MockQueueableContext());  // page 3 succeeds

Async.chunk(new AccountRecalcJob(), ChunkSource.of(records))
	.chunkSize(2)
	.mockId('recalc-run')
	.stopRemainingChunksOnFailure()
	.enqueue();
```

A cursor run is testable as-is: `Database.getCursor(...)` works inside a test
against data the test inserted. Prefer that whenever the query itself is the thing
you want to cover, because an in-memory source never executes your SOQL.

Design for the swap. A service that hardcodes its source cannot be told to use
another one:

```apex
// Hard to test: the source is welded in
public static void recalcAll() {
  Async.chunk(new AccountRecalcJob(), ChunkSource.query('SELECT Id FROM Account')).enqueue();
}

// Easy to test: the caller decides
public static void recalcAll(ChunkSource source) {
  Async.chunk(new AccountRecalcJob(), source).enqueue();
}
```

Cursor expiry, the daily cursor allocation, and the 2,000 record fetch ceiling are
platform behaviours. They cannot be reproduced in a test, and faking them would
test the fake rather than the framework.

See [Testing Async Jobs](/explanations/testing-async-jobs) for worked examples.

## Methods

### INIT

#### chunk

Constructs a new `ChunkBuilder` for the given job and record source. The source is
mandatory.

**Signature**

```apex
ChunkBuilder Async.chunk(ChunkJob job, ChunkSource source);
ChunkBuilder QueueableBuilder.chunk(ChunkJob job, ChunkSource source);
```

Use `Async.chunk(...)` to start a chain with the run, and
`.chunk(...)` on a `QueueableBuilder` to put a run after jobs you already chained.

**Example**

```apex
Async.chunk(new AccountRecalcJob(), ChunkSource.of(records));

Async.queueable(new PrepareJob()).chunk(new AccountRecalcJob(), ChunkSource.of(records));
```

### Source

`ChunkSource` is the pluggable seam between the framework and your data. Use a
factory, or extend `ChunkSource` for a fully custom source.

| Factory                                            | Source                                 |
| -------------------------------------------------- | -------------------------------------- |
| `ChunkSource.of(List<SObject>)`                    | in-memory records (also the test fake) |
| `ChunkSource.ofIds(Set<Id>)`                       | id-only source                         |
| `ChunkSource.cursor(Database.Cursor)`              | wraps an existing SOQL cursor          |
| `ChunkSource.query(String soql)`                   | opens a cursor over the query          |
| `ChunkSource.query(String soql, AccessLevel accessLevel)` | same, with an explicit access level |
| `ChunkSource.query(String soql, Map<String, Object> binds)` | same, with bind variables     |
| `ChunkSource.query(String soql, Map<String, Object> binds, AccessLevel accessLevel)` | binds plus access level |

The two abstract methods mirror `Database.Cursor`, so wrapping a cursor is a
straight delegate and a custom source only has to answer the same two questions.
`maxChunkSize()` is how a source declares its own page ceiling, if it has one.

**Signature**

```apex
abstract Integer getNumRecords();
abstract List<SObject> fetch(Integer position, Integer count);
virtual Integer maxChunkSize(); // null means no ceiling
```

### Build

#### chunkSize

Sets how many records each page processes. Must be positive, and no larger than
the source's `maxChunkSize()` when it declares one. Defaults to `200`.

A cursor source caps a page at 2,000 records, the most `Database.Cursor.fetch()`
returns. An in-memory source has no ceiling; what bounds a page there is your
`work(...)` body, so keep DML rows, heap and CPU in mind before going large.

**Signature**

```apex
ChunkBuilder chunkSize(Integer chunkSize);
```

**Example**

```apex
Async.chunk(new AccountRecalcJob(), ChunkSource.of(records)).chunkSize(50);
```

#### stopRemainingChunksOnFailure

Stops the run when a chunk exhausts its retries. Off by default (remaining chunks
still run).

**Signature**

```apex
ChunkBuilder stopRemainingChunksOnFailure();
```

#### dependsOn

Runs the chunk run only when an earlier chain member had the required outcome.
Same semantics as [Queueable dependsOn](/api/queueable#dependson).

**Signature**

```apex
ChunkBuilder dependsOn(Async.Dependency dependency);
```

**Example**

```apex
Async.queueable(new PrepareJob())
	.chunk(new AccountRecalcJob(), ChunkSource.of(records))
	.dependsOn(Async.afterPrevious().succeeded())
	.enqueue();
```

#### priority

Sets the chunk job priority.

**Signature**

```apex
ChunkBuilder priority(Integer priority);
```

#### delay

Sets a one-time delay in minutes before the first page runs. It does not repeat
on later pages.

**Signature**

```apex
ChunkBuilder delay(Integer delay);
```

#### delayBetweenChunks

Throttles the run by waiting this many minutes before each page after the first.
Use it to spread DML/callout load or stay under per-hour async limits. Salesforce
caps enqueue delay at 10 minutes.

**Signature**

```apex
ChunkBuilder delayBetweenChunks(Integer minutes);
```

#### retry

Sets the maximum retry attempts per chunk. Must be `0..10`.

**Signature**

```apex
ChunkBuilder retry(Integer maxRetries);
```

#### backoff

Sets the retry backoff strategy. See the [Queueable backoff table](/api/queueable#backoff).

**Signature**

```apex
ChunkBuilder backoff(Backoff backoff);
```

#### retryOn

Restricts retries to the given exception type(s).

**Signature**

```apex
ChunkBuilder retryOn(Type exceptionType);
ChunkBuilder retryOn(List<Type> exceptionTypes);
```

#### mockId

Sets a mock id for the chunk job. See [AsyncMock](/api/async-mock).

**Signature**

```apex
ChunkBuilder mockId(String mockId);
```

#### keepChunkPages

By default a settled page is pruned from the chain once its result is recorded,
so the run stays flat at any scale. Call this to retain settled pages in
`queueableChainState.jobs` instead. Off by default; not for large runs, since kept
pages grow the serialized chain state.

This only affects what you can read from inside the run. Every page writes its own
`AsyncResult__c` either way, so you do not need it to see the results of a run.

**Signature**

```apex
ChunkBuilder keepChunkPages();
```

### Execute

#### chain

Chains a job to run after the last page of the run and returns a `QueueableBuilder`
for it, so the rest of the chain reads exactly like a normal one.

**Signature**

```apex
QueueableBuilder chain(QueueableJob nextJob);
Async.Result chain();
```

**Example**

```apex
Async.chunk(new AccountRecalcJob(), ChunkSource.of(records))
	.chunkSize(50)
	.chain(new NotifyJob())
	.enqueue();
```

#### chunk next run

Chains a second run after the current one and returns its `ChunkBuilder`, so
multi-stage pipelines stay fluent. Every page of the first run completes before
the first page of the second one starts.

**Signature**

```apex
ChunkBuilder chunk(ChunkJob nextChunkJob, ChunkSource nextSource);
```

**Example**

```apex
Async.chunk(new StageOneJob(), ChunkSource.query('SELECT Id FROM Account WHERE ...'))
	.chunkSize(200)
	.chunk(new StageTwoJob(), ChunkSource.query('SELECT Id FROM Contact WHERE ...'))
	.chunkSize(100)
	.enqueue();
```

`dependsOn(Async.afterPrevious())` on the second run resolves against the first
run's **run-level** outcome, so `succeeded()` means every page of stage one passed.

```apex
Async.chunk(new StageOneJob(), source)
	.chunkSize(200)
	.chunk(new StageTwoJob(), otherSource)
	.dependsOn(Async.afterPrevious().succeeded())
	.enqueue();
```

Each source is evaluated when its builder is created, not when its run starts. If
stage two must query rows that stage one produces, build it inside stage one's
`work(...)` instead, or use a plain `chain(...)` job that enqueues it.

#### enqueue

Enqueues the run and returns the `Async.Result` for the first page. Enqueuing an
empty source is a safe no-op: the run itself is skipped, and any jobs already
chained still run.

**Signature**

```apex
Async.Result enqueue();
```

**Example**

```apex
Async.Result result = Async.chunk(new AccountRecalcJob(), ChunkSource.of(records))
	.chunkSize(50)
	.enqueue();
```
