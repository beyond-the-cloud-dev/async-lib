# AsyncMock API

Apex class `AsyncMock.cls`.

**Common Queueable mocking example:**

```apex
@IsTest
static void shouldMockQueueableContext() {
	AsyncMock.whenQueueable('account-creator')
		.thenReturn(new AsyncMock.MockQueueableContext());

	Test.startTest();
	Async.queueable(new AccountCreatorJob())
		.mockId('account-creator')
		.enqueue();
	Test.stopTest();
}
```

**Common job failure mocking example:**

```apex
@IsTest
static void shouldMockJobFailure() {
	AsyncMock.whenQueueable('flaky-job')
		.thenThrow(new CalloutException('service unavailable'));

	Test.startTest();
	Async.queueable(new SyncAccountsJob()).mockId('flaky-job').retry(1).enqueue();
	Test.stopTest();
	// The job never runs. It fails, retries and records exactly as if it had thrown.
}
```

**Common Finalizer mocking example:**

```apex
@IsTest
static void shouldMockFinalizerContext() {
	AsyncMock.whenFinalizer('error-handler')
		.thenThrow(new DmlException('Parent job failed'));

	Test.startTest();
	Async.queueable(new ParentJobWithFinalizer('error-handler')).enqueue();
	Test.stopTest();
}
```

::: tip
For finalizer mocking, the `mockId` must be set on the finalizer itself (via `attachFinalizer()` inside `work()`), not on the parent job.
:::

For testing patterns and best practices, see [Testing Async Jobs](/explanations/testing-async-jobs).

## Methods

The following are methods for using AsyncMock in tests:

[**INIT - Finalizer**](#init---finalizer)

- [`whenFinalizer(String mockId)`](#whenfinalizer)
- [`whenFinalizerDefault()`](#whenfinalizerdefault)

[**INIT - Queueable**](#init---queueable)

- [`whenQueueable(String mockId)`](#whenqueueable)
- [`whenQueueableDefault()`](#whenqueueabledefault)

[**Build - FinalizerMockSetup**](#build---finalizermocksetup)

- [`thenReturn(FinalizerContext ctx)`](#thenreturn-finalizercontext)
- [`thenReturn(ParentJobResult result)`](#thenreturn-parentjobresult)
- [`thenThrow(Exception ex)`](#thenthrow)

[**Build - QueueableMockSetup**](#build---queueablemocksetup)

- [`thenReturn(QueueableContext ctx)`](#thenreturn-queueablecontext)
- [`thenReturn(Id jobId)`](#thenreturn-id)
- [`thenThrow(Exception ex)`](#thenthrow-1)

[**Utility**](#utility)

- [`reset()`](#reset)
- [`hasFinalizerMock(String mockId)`](#hasfinalizermock)
- [`hasQueueableMock(String mockId)`](#hasqueueablemock)
- [`getFinalizerContext(String mockId)`](#getfinalizercontext)
- [`getQueueableContext(String mockId)`](#getqueueablecontext)

[**Mock Context Classes**](#mock-context-classes)

- [`MockFinalizerContext`](#mockfinalizercontext)
- [`MockQueueableContext`](#mockqueueablecontext)

### INIT - Finalizer

#### whenFinalizer

Sets up a mock for a specific finalizer identified by mockId.

**Signature**

```apex
static FinalizerMockSetup whenFinalizer(String mockId);
```

**Example**

```apex
AsyncMock.whenFinalizer('error-handler')
	.thenReturn(ParentJobResult.SUCCESS);
```

#### whenFinalizerDefault

Sets up a default mock that applies when no specific mockId matches or when a specific mock is exhausted.

**Signature**

```apex
static FinalizerMockSetup whenFinalizerDefault();
```

**Example**

```apex
AsyncMock.whenFinalizerDefault()
	.thenReturn(ParentJobResult.SUCCESS);

Test.startTest();
Async.queueable(new ParentJobWithFinalizer('job-1')).enqueue();
Async.queueable(new ParentJobWithFinalizer('job-2')).enqueue();
Test.stopTest();
```

### INIT - Queueable

#### whenQueueable

Sets up a mock for a specific queueable job identified by mockId.

**Signature**

```apex
static QueueableMockSetup whenQueueable(String mockId);
```

**Example**

```apex
AsyncMock.whenQueueable('account-creator')
	.thenReturn(new AsyncMock.MockQueueableContext());
```

#### whenQueueableDefault

Sets up a default mock that applies when no specific mockId matches or when a specific mock is exhausted.

**Signature**

```apex
static QueueableMockSetup whenQueueableDefault();
```

**Example**

```apex
AsyncMock.whenQueueableDefault()
	.thenReturn(new AsyncMock.MockQueueableContext());
```

### Build - FinalizerMockSetup

#### thenReturn (FinalizerContext)

Adds a `FinalizerContext` to the mock queue. Each call to `getFinalizerContext` consumes one context from the queue (FIFO).

**Signature**

```apex
FinalizerMockSetup thenReturn(FinalizerContext ctx);
```

**Example**

```apex
AsyncMock.whenFinalizer('multi-test')
	.thenReturn(new AsyncMock.MockFinalizerContext()
		.setResult(ParentJobResult.SUCCESS))
	.thenReturn(new AsyncMock.MockFinalizerContext()
		.setResult(ParentJobResult.UNHANDLED_EXCEPTION));
```

#### thenReturn (ParentJobResult)

Convenience method that creates a `MockFinalizerContext` with the specified result.

**Signature**

```apex
FinalizerMockSetup thenReturn(ParentJobResult result);
```

**Example**

```apex
AsyncMock.whenFinalizer('my-job')
	.thenReturn(ParentJobResult.SUCCESS)
	.thenReturn(ParentJobResult.UNHANDLED_EXCEPTION)
	.thenReturn(ParentJobResult.SUCCESS);
```

#### thenThrow

Creates a `MockFinalizerContext` with `UNHANDLED_EXCEPTION` result and the specified exception.

**Signature**

```apex
FinalizerMockSetup thenThrow(Exception ex);
```

**Example**

```apex
AsyncMock.whenFinalizer('error-handler')
	.thenThrow(new DmlException('Parent job failed'));

Test.startTest();
Async.queueable(new ParentJobWithFinalizer('error-handler')).enqueue();
Test.stopTest();

Account errorLog = [SELECT Name, Description FROM Account LIMIT 1];
Assert.areEqual('Parent job failed', errorLog.Description);
```

### Build - QueueableMockSetup

#### thenReturn (QueueableContext)

Adds a `QueueableContext` to the mock queue. Each call to `getQueueableContext` consumes one context from the queue (FIFO).

**Signature**

```apex
QueueableMockSetup thenReturn(QueueableContext ctx);
```

**Example**

```apex
AsyncMock.whenQueueable('my-job')
	.thenReturn(new AsyncMock.MockQueueableContext().setJobId('707xx0000000001'));
```

#### thenReturn (Id)

Convenience method that creates a `MockQueueableContext` with the specified job ID.

**Signature**

```apex
QueueableMockSetup thenReturn(Id jobId);
```

**Example**

```apex
AsyncMock.whenQueueable('my-job')
	.thenReturn('707xx0000000001AAA');
```

#### thenThrow

Makes the job fail instead of running. The exception is raised where the job body
would have run, so everything downstream behaves as if the job had thrown it
itself: rollback, retry classification and backoff, the `FAILED` `AsyncResult__c`,
and any chain or chunk failure policy. Use it to test a failure path without
writing a job class that exists only to blow up.

**Signature**

```apex
QueueableMockSetup thenThrow(Exception ex);
```

**Example**

```apex
AsyncMock.whenQueueable('flaky-job')
	.thenThrow(new CalloutException('service unavailable'));

Test.startTest();
Async.queueable(new SyncAccountsJob())
	.mockId('flaky-job')
	.retry(1)
	.enqueue();
Test.stopTest();
```

::: tip Picking which run fails
The mock is a queue, so mixing `thenReturn` and `thenThrow` chooses which
execution fails. On a [chunk run](/api/chunk) that means choosing which page fails,
since every page consumes one entry:

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

:::

### Utility

#### reset

Clears all mock setups (both specific and default mocks).

**Signature**

```apex
static void reset();
```

**Example**

```apex
AsyncMock.whenFinalizer('test').thenReturn(ParentJobResult.SUCCESS);
AsyncMock.whenQueueable('test').thenReturn(new AsyncMock.MockQueueableContext());

AsyncMock.reset();

Assert.isNull(AsyncMock.getFinalizerContext('test'));
Assert.isNull(AsyncMock.getQueueableContext('test'));
```

#### hasFinalizerMock

Checks if a finalizer mock exists for the given mockId or if a default mock is configured.

**Signature**

```apex
static Boolean hasFinalizerMock(String mockId);
```

**Example**

```apex
AsyncMock.whenFinalizer('my-job').thenReturn(ParentJobResult.SUCCESS);

Assert.isTrue(AsyncMock.hasFinalizerMock('my-job'));
Assert.isFalse(AsyncMock.hasFinalizerMock('other-job'));
```

#### hasQueueableMock

Checks if a queueable mock exists for the given mockId or if a default mock is configured.

**Signature**

```apex
static Boolean hasQueueableMock(String mockId);
```

**Example**

```apex
AsyncMock.whenQueueable('my-job').thenReturn(new AsyncMock.MockQueueableContext());

Assert.isTrue(AsyncMock.hasQueueableMock('my-job'));
Assert.isFalse(AsyncMock.hasQueueableMock('other-job'));
```

#### getFinalizerContext

Retrieves and removes the next `FinalizerContext` from the mock queue. Falls back to default mock if specific mock is exhausted.

**Signature**

```apex
static FinalizerContext getFinalizerContext(String mockId);
```

**Example**

```apex
AsyncMock.whenFinalizerDefault().thenReturn(ParentJobResult.SUCCESS);
AsyncMock.whenFinalizer('special').thenThrow(new DmlException('Error'));

FinalizerContext ctx1 = AsyncMock.getFinalizerContext('special');
FinalizerContext ctx2 = AsyncMock.getFinalizerContext('special');

Assert.areEqual(ParentJobResult.UNHANDLED_EXCEPTION, ctx1.getResult());
Assert.areEqual(ParentJobResult.SUCCESS, ctx2.getResult()); // Falls back to default
```

#### getQueueableContext

Retrieves and removes the next `QueueableContext` from the mock queue. Falls back to default mock if specific mock is exhausted.

**Signature**

```apex
static QueueableContext getQueueableContext(String mockId);
```

**Example**

```apex
AsyncMock.whenQueueableDefault().thenReturn(new AsyncMock.MockQueueableContext());
AsyncMock.whenQueueable('special').thenReturn(new AsyncMock.MockQueueableContext());

QueueableContext ctx1 = AsyncMock.getQueueableContext('special');
QueueableContext ctx2 = AsyncMock.getQueueableContext('special');

Assert.isNotNull(ctx1);
Assert.isNotNull(ctx2); // Falls back to default
```

### Mock Context Classes

#### MockFinalizerContext

Implements `System.FinalizerContext` for test scenarios.

**Signature**

```apex
public class MockFinalizerContext implements System.FinalizerContext
```

**Build Methods**

| Method | Description |
|--------|-------------|
| `setResult(ParentJobResult result)` | Sets the parent job result |
| `setException(Exception ex)` | Sets exception and auto-sets result to `UNHANDLED_EXCEPTION` |
| `setJobId(Id jobId)` | Sets the async apex job ID |

**Interface Methods**

| Method | Description |
|--------|-------------|
| `getResult()` | Returns the configured `ParentJobResult` |
| `getException()` | Returns the configured exception |
| `getAsyncApexJobId()` | Returns the configured job ID |
| `getRequestId()` | Returns `'mock-request-id'` |

**Example**

```apex
ErrorHandlerFinalizer finalizer = new ErrorHandlerFinalizer();
finalizer.finalizerCtx = new AsyncMock.MockFinalizerContext()
	.setResult(ParentJobResult.UNHANDLED_EXCEPTION)
	.setException(new DmlException('Direct test error'));

finalizer.work();
```

#### MockQueueableContext

Implements `System.QueueableContext` for test scenarios.

**Signature**

```apex
public class MockQueueableContext implements System.QueueableContext
```

**Build Methods**

| Method | Description |
|--------|-------------|
| `setJobId(Id jobId)` | Sets the job ID |
| `setException(Exception ex)` | Makes the job fail with this exception instead of running |

**Interface Methods**

| Method | Description |
|--------|-------------|
| `getJobId()` | Returns the configured job ID |
| `getException()` | Returns the failure the job will be given, if any |

**Example**

```apex
AccountCreatorJob job = new AccountCreatorJob('Direct Test');
job.queueableCtx = new AsyncMock.MockQueueableContext();

job.work();
```
