# Chunk API

Apex classes `ChunkBuilder.cls`, `ChunkJob.cls`, `IdChunkJob.cls`, and
`ChunkSource.cls`.

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

**Common IdChunkJob class example:**

When you only need the record ids, extend `IdChunkJob` and override
`work(Set<Id> ids)`. The framework plucks the ids from each fetched page.

```apex
public class AccountCloseJob extends IdChunkJob {
  public override void work(Set<Id> ids) {
    // requery or process by id
  }
}
```

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
Use the bind overload rather than concatenating user input, and add
`WITH USER_MODE` to the query if the run must respect the current user's field and
record access (a cursor opened by `ChunkSource` runs in system mode, like
`Database.getCursor`). The framework hands each page to your `work(...)` as
queried; it does not strip fields.

```apex
ChunkSource.query(
  'SELECT Id FROM Account WHERE Industry = :industry WITH USER_MODE',
  new Map<String, Object>{ 'industry' => userInput }
);
```

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
| `ChunkSource.query(String soql, Map<String, Object> binds)` | same, with bind variables     |

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
