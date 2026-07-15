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

## Failure handling

Two independent levels:

- **Per chunk (retry).** A page that throws retries per `.retry(...)` /
  `.backoff(...)`, exactly like a `QueueableJob`. Each terminal page records an
  `AsyncResult__c` row (`COMPLETED` or `FAILED`).
- **Across the run.** By default the run keeps processing the remaining chunks
  even if one fails (best-effort, `Batchable`-like). Call
  `.stopRemainingChunksOnFailure()` to stop the run when a chunk exhausts its
  retries.

## Cursor governor caps

`ChunkSource.cursor(...)` / `ChunkSource.query(...)` open a SOQL cursor. Salesforce
enforces cursor limits you should weigh against a `Database.Batchable`:

| Limit                                    | Value          |
| ---------------------------------------- | -------------- |
| Rows per cursor                          | 50 million     |
| Cursor fetch calls per day               | see Salesforce cursor limits |
| Cursor lifespan                          | 2 days         |
| Concurrent cursors                       | see Salesforce cursor limits |

`ChunkSource.of(...)` / `ChunkSource.ofIds(...)` hold records in memory instead, so
they are bounded by heap, not cursor limits. Prefer them for smaller sets and for
tests.

## Security

`ChunkSource.query(String soql)` runs the SOQL you pass, so you own its safety.
Bind user input, and add `WITH USER_MODE` to the query if the run must respect the
current user's field and record access. The framework hands each page to your
`work(...)` as queried; it does not strip fields.

## Methods

### INIT

#### chunk

Constructs a new `ChunkBuilder` for the given job and record source. The source is
mandatory.

**Signature**

```apex
ChunkBuilder chunk(ChunkJob job, ChunkSource source);
```

**Example**

```apex
Async.chunk(new AccountRecalcJob(), ChunkSource.of(records));
```

### Source

`ChunkSource` is the pluggable seam between the framework and your data. Use a
factory, or extend `ChunkSource` for a fully custom source.

| Factory                             | Source                                       |
| ----------------------------------- | -------------------------------------------- |
| `ChunkSource.of(List<SObject>)`     | in-memory records (also the test fake)       |
| `ChunkSource.ofIds(Set<Id>)`        | id-only source                               |
| `ChunkSource.cursor(Database.Cursor)` | wraps an existing SOQL cursor              |
| `ChunkSource.query(String soql)`    | opens a cursor over the query                |

**Signature**

```apex
abstract Integer size();
abstract List<SObject> fetch(Integer offset, Integer count);
```

### Build

#### chunkSize

Sets how many records each page processes. Must be a positive integer. Defaults to
`200`.

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
so the run stays flat at any scale (each page still writes its own
`AsyncResult__c` when result tracking is enabled). Call this to retain settled
pages in `queueableChainState.jobs` for introspection instead. Off by default;
not for large runs, since kept pages grow the serialized chain state.

**Signature**

```apex
ChunkBuilder keepChunkPages();
```

### Execute

#### enqueue

Enqueues the run and returns the `Async.Result` for the first page. Enqueuing an
empty source is a safe no-op (nothing is enqueued and `result.salesforceJobId` is
`null`).

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
