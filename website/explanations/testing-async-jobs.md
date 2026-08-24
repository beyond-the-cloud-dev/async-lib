---
outline: deep
---

# Testing Async Jobs

## TL;DR

Testing asynchronous jobs in Salesforce presents unique challenges because
`QueueableContext` and `FinalizerContext` are system-provided during runtime.
AsyncMock provides mock implementations of these context interfaces, enabling you to:

- Test finalizer error handling without triggering actual job failures
- Test queueable job behavior with controlled context
- Direct unit testing of job `work()` methods without `Test.startTest()/stopTest()`
- Queue-based mock consumption for testing multiple invocations

The rule is **pushed by the platform, mock it. Passed by you, swap it.** A
`ChunkSource` falls in the second group, so a chunk run has no mock and needs none:
hand it `ChunkSource.of(records)` or your own subclass. See
[Pattern 5](#pattern-5-testing-a-chunk-job-without-a-cursor) and
[Pattern 6](#pattern-6-a-custom-chunksource). The context objects inside a chunk
page are still pushed, so those keep using `mockId(...)`
([Pattern 7](#pattern-7-mocking-context-inside-a-chunk-page)).

View the full [AsyncMock API](/api/async-mock) documentation for method details.

## The Testing Challenge

### Why Standard Testing Falls Short

When testing async jobs traditionally, you face these limitations:

1. **Limited Context Control**: You cannot control what `FinalizerContext` returns
2. **No Exception Simulation**: Cannot easily simulate `ParentJobResult.UNHANDLED_EXCEPTION`
3. **Integration-Only Testing**: Must use `Test.startTest()/stopTest()` for all scenarios
4. **No Multiple Invocation Testing**: Hard to test a job that handles multiple calls differently

### Traditional Approach

```apex
@IsTest
static void traditionalTest() {
    Test.startTest();
    Async.queueable(new MyJob()).enqueue();
    Test.stopTest();

    // Can only verify end results, not intermediate states
    // Cannot test error handling paths
    // Cannot test finalizer behavior with exceptions
}
```

### The AsyncMock Solution

AsyncMock provides:

1. **Mock Context Classes**: Full implementations of Salesforce context interfaces
2. **Fluent Setup API**: Easy-to-read test setup with `whenFinalizer().thenReturn()`
3. **Queue-Based Mocks**: Multiple mock responses for sequential calls
4. **Default Fallback**: Default mocks when specific mockId isn't found

## Testing Patterns

### Pattern 1: Testing Finalizer Error Handling

Test how your finalizer handles job failures without actually causing a failure.

```apex
public class ErrorHandlerFinalizer extends QueueableJob.Finalizer {
    public override void work() {
        FinalizerContext ctx = this.finalizerCtx;
        if (ctx?.getResult() == ParentJobResult.UNHANDLED_EXCEPTION) {
            insert new Account(
                Name = 'Error Log',
                Description = ctx.getException()?.getMessage()
            );
        }
    }
}

public class ParentJobWithFinalizer extends QueueableJob {
    private String mockId;

    public ParentJobWithFinalizer(String mockId) {
        this.mockId = mockId;
    }

    public override void work() {
        Async.queueable(new ErrorHandlerFinalizer())
            .mockId(mockId)
            .attachFinalizer();
    }
}
```

**Test with mocked exception:**

```apex
@IsTest
static void shouldHandleJobFailure() {
    AsyncMock.whenFinalizer('error-handler')
        .thenThrow(new DmlException('Parent job failed'));

    Test.startTest();
    Async.queueable(new ParentJobWithFinalizer('error-handler')).enqueue();
    Test.stopTest();

    Account errorLog = [SELECT Name, Description FROM Account LIMIT 1];
    Assert.areEqual('Error Log', errorLog.Name);
    Assert.areEqual('Parent job failed', errorLog.Description);
}
```

**Test with success result:**

```apex
@IsTest
static void shouldNotCreateLogOnSuccess() {
    AsyncMock.whenFinalizer('error-handler')
        .thenReturn(ParentJobResult.SUCCESS);

    Test.startTest();
    Async.queueable(new ParentJobWithFinalizer('error-handler')).enqueue();
    Test.stopTest();

    Assert.areEqual(0, [SELECT COUNT() FROM Account]);
}
```

### Pattern 2: Direct Unit Testing

Test job logic directly without `Test.startTest()/stopTest()` by injecting mock contexts.

```apex
public class AccountCreatorJob extends QueueableJob {
    private String accountName;

    public AccountCreatorJob(String accountName) {
        this.accountName = accountName;
    }

    public override void work() {
        Id jobId = this.queueableCtx?.getJobId();
        insert new Account(Name = accountName, Description = 'Job: ' + jobId);
    }
}
```

**Direct test:**

```apex
@IsTest
static void shouldCreateAccountDirectly() {
    AccountCreatorJob job = new AccountCreatorJob('Direct Test');
    job.queueableCtx = new AsyncMock.MockQueueableContext();

    job.work();

    Account acc = [SELECT Name, Description FROM Account LIMIT 1];
    Assert.areEqual('Direct Test', acc.Name);
    Assert.isNotNull(acc.Description);
}
```

**Finalizer direct test:**

```apex
@IsTest
static void shouldTestFinalizerDirectly() {
    ErrorHandlerFinalizer finalizer = new ErrorHandlerFinalizer();
    finalizer.finalizerCtx = new AsyncMock.MockFinalizerContext()
        .setResult(ParentJobResult.UNHANDLED_EXCEPTION)
        .setException(new DmlException('Direct test error'));

    finalizer.work();

    Account errorLog = [SELECT Name, Description FROM Account LIMIT 1];
    Assert.areEqual('Error Log', errorLog.Name);
    Assert.areEqual('Direct test error', errorLog.Description);
}
```

### Pattern 3: Multiple Invocation Testing

Test jobs that should behave differently on sequential calls using queue-based mocks.

```apex
@IsTest
static void shouldHandleMultipleInvocations() {
    AsyncMock.whenFinalizer('multi-test')
        .thenReturn(ParentJobResult.SUCCESS)
        .thenThrow(new DmlException('Second call failed'))
        .thenReturn(ParentJobResult.SUCCESS);

    Test.startTest();
    Async.queueable(new ParentJobWithFinalizer('multi-test')).enqueue();
    Async.queueable(new ParentJobWithFinalizer('multi-test')).enqueue();
    Async.queueable(new ParentJobWithFinalizer('multi-test')).enqueue();
    Test.stopTest();

    // Only the second call created an error log
    Assert.areEqual(1, [SELECT COUNT() FROM Account]);
    Assert.areEqual(
        'Second call failed',
        [SELECT Description FROM Account LIMIT 1].Description
    );
}
```

### Pattern 4: Default Mock Fallback

Use default mocks for jobs without specific mock IDs.

```apex
@IsTest
static void shouldUseDefaultMock() {
    AsyncMock.whenFinalizerDefault()
        .thenReturn(ParentJobResult.SUCCESS);

    Test.startTest();
    // All these jobs use the default mock
    Async.queueable(new ParentJobWithFinalizer('job-1')).enqueue();
    Async.queueable(new ParentJobWithFinalizer('job-2')).enqueue();
    Test.stopTest();

    Assert.areEqual(0, [SELECT COUNT() FROM Account]);
}
```

**Combining specific and default mocks:**

```apex
@IsTest
static void shouldFallbackToDefault() {
    AsyncMock.whenFinalizerDefault().thenReturn(ParentJobResult.SUCCESS);
    AsyncMock.whenFinalizer('special').thenThrow(new DmlException('Error'));

    // First call uses specific mock, then falls back to default
    FinalizerContext ctx1 = AsyncMock.getFinalizerContext('special');
    FinalizerContext ctx2 = AsyncMock.getFinalizerContext('special');

    Assert.areEqual(ParentJobResult.UNHANDLED_EXCEPTION, ctx1.getResult());
    Assert.areEqual(ParentJobResult.SUCCESS, ctx2.getResult()); // Falls back to default
}
```

### Pattern 5: Testing a Chunk Job Without a Cursor

`ChunkSource.of(...)` is the in-memory source and doubles as the test fake, so a
chunk job can be exercised without inserting data and opening a live cursor. Swap
it for `ChunkSource.query(...)` in production code only.

```apex
@IsTest
static void shouldProcessEveryPage() {
    List<Account> accounts = new List<Account>();
    for (Integer i = 0; i < 6; i++) {
        accounts.add(new Account(Name = 'Test ' + i));
    }
    insert accounts;

    Test.startTest();
    Async.chunk(new AccountRecalcJob(), ChunkSource.of(accounts))
        .chunkSize(2)
        .enqueue();
    Test.stopTest();

    Assert.areEqual(6, [SELECT COUNT() FROM Account WHERE Description = 'Recalculated']);
}
```

To assert a single page in isolation, call `work(chunk)` directly with the records
you care about. No enqueue, no chain, no async boundary:

```apex
@IsTest
static void shouldRecalcOnePage() {
    new AccountRecalcJob().work(accounts);

    Assert.areEqual(2, [SELECT COUNT() FROM Account WHERE Description = 'Recalculated']);
}
```

**Why there is no ChunkSource mock**

A chunk page is an ordinary job in the chain, so every pattern above already
applies to a run. `AsyncMock` handles what the platform **pushes** into a job: the
contexts you cannot construct, and the parent outcome a finalizer reacts to.

A `ChunkSource` is **passed**, by you, at the call site. Swapping it is the test
seam, so a mock registry would only add a second way to do the same thing, and a
worse one: it changes what production code does behind its back.

The rule of thumb: **pushed by the platform, mock it. Passed by you, swap it.**

Design your service so the swap is possible:

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

**Testing a cursor run**

Nothing is blocked. `Database.getCursor(...)` runs inside a test against data the
test inserted, and the cursor survives every hop of the run exactly as it does in
production:

```apex
@IsTest
static void shouldPageACursor() {
    insert accounts; // 6 of them

    Test.startTest();
    Async.chunk(new AccountRecalcJob(), ChunkSource.query('SELECT Id FROM Account'))
        .chunkSize(2)
        .enqueue();
    Test.stopTest();

    Assert.areEqual(6, [SELECT COUNT() FROM Account WHERE Description = 'Recalculated']);
}
```

Use the real query whenever the query is the thing you want to cover. A test built
on `ChunkSource.of(...)` never executes your SOQL, so a bad field or a wrong WHERE
clause survives it.

What no test can reach: cursor expiry after 2 days, the daily cursor allocation,
and the 2,000 record `fetch()` ceiling. Faking those would test the fake.

### Pattern 6: A Custom ChunkSource

`ChunkSource` is an abstract class, so a test can supply one that fabricates
records instead of inserting them. This is how you page 100,000 records without a
single DML statement:

```apex
private class SyntheticChunkSource extends ChunkSource {
    private Integer total;

    public SyntheticChunkSource(Integer total) {
        this.total = total;
    }

    public override Integer getNumRecords() {
        return total;
    }

    public override List<SObject> fetch(Integer position, Integer count) {
        List<Account> page = new List<Account>();
        for (Integer i = position; i < Math.min(position + count, total); i++) {
            page.add(new Account(Name = 'Synthetic ' + i));
        }
        return page;
    }
}
```

The same trick covers a broken source. Throw from `fetch(...)` and the page fails
and retries like any other page failure:

```apex
private class ExplodingChunkSource extends ChunkSource {
    public override Integer getNumRecords() {
        return 4;
    }

    public override List<SObject> fetch(Integer position, Integer count) {
        throw new CalloutException('source unavailable');
    }
}
```

```apex
Async.chunk(new AccountRecalcJob(), new ExplodingChunkSource())
    .chunkSize(2)
    .retry(1)
    .enqueue();
// AsyncResult__c: Status__c = FAILED, RetryAttempts__c = 1
```

### Pattern 7: Mocking Inside a Chunk Page

A chunk page is an ordinary job in the chain, so `mockId(...)` works on a chunk run
exactly as it does on a queueable:

```apex
@IsTest
static void shouldReadMockedContext() {
    AsyncMock.whenQueueable('chunk-page')
        .thenReturn(new AsyncMock.MockQueueableContext().setJobId(mockJobId));

    Test.startTest();
    Async.chunk(new AccountRecalcJob(), ChunkSource.of(accounts))
        .chunkSize(2)
        .mockId('chunk-page')
        .enqueue();
    Test.stopTest();
}
```

The finalizer story carries over too. Attach a finalizer inside `work(chunk)` and
you can tell it its page blew up, without engineering a page that actually fails:

```apex
public class AccountRecalcJob extends ChunkJob {
    public override void work(List<SObject> chunk) {
        Async.queueable(new ErrorHandlerFinalizer()).mockId('page-error-handler').attachFinalizer();
        // ... work on chunk ...
    }
}
```

```apex
@IsTest
static void shouldHandleAPageFailure() {
    AsyncMock.whenFinalizer('page-error-handler').thenThrow(new DmlException('Page blew up'));

    Test.startTest();
    Async.chunk(new AccountRecalcJob(), ChunkSource.of(accounts)).chunkSize(2).enqueue();
    Test.stopTest();

    Assert.areEqual(1, [SELECT COUNT() FROM Account WHERE Name = 'Error Log']);
}
```

As with any job, the `mockId` for finalizer mocking goes on the finalizer, not on
the chunk job.

To make the run itself take its failure path (retry,
`stopRemainingChunksOnFailure`, the summary result, a skipped dependent job), use
`thenThrow`. Every page consumes one entry from the mock queue, so the queue
decides which page fails:

```apex
@IsTest
static void shouldHaltAfterTheSecondPage() {
    AsyncMock.whenQueueable('recalc-run')
        .thenReturn(new AsyncMock.MockQueueableContext())  // page 1 succeeds
        .thenThrow(new CalloutException('boom'));          // page 2 fails

    Test.startTest();
    Async.chunk(new AccountRecalcJob(), ChunkSource.of(accounts))
        .chunkSize(2)
        .mockId('recalc-run')
        .stopRemainingChunksOnFailure()
        .enqueue();
    Test.stopTest();

    Assert.areEqual(2, [SELECT COUNT() FROM Account WHERE Description = 'Recalculated']);
}
```

Throwing from `work(chunk)` or from a `ChunkSource` subclass (Pattern 6) is still
the right tool when the failure depends on the data itself.

## Best Practices

### 1. Use mockId for Targeted Mocking

Always use meaningful mock IDs that describe the test scenario:

```apex
// Good
AsyncMock.whenFinalizer('payment-error-handler').thenThrow(new PaymentException());
AsyncMock.whenFinalizer('notification-sender').thenReturn(ParentJobResult.SUCCESS);

// Avoid generic IDs
AsyncMock.whenFinalizer('test').thenThrow(new Exception());
```

### 2. Reset Mocks When Needed

If running multiple tests that share mock state, reset between tests:

```apex
@IsTest
static void testOne() {
    AsyncMock.whenFinalizer('test').thenReturn(ParentJobResult.SUCCESS);
    // ... test code
}

@IsTest
static void testTwo() {
    AsyncMock.reset(); // Clean slate
    AsyncMock.whenFinalizer('test').thenThrow(new DmlException());
    // ... test code
}
```

### 3. Prefer Direct Testing When Possible

Direct testing is faster and more focused:

```apex
// Faster - direct unit test
@IsTest
static void directTest() {
    MyJob job = new MyJob();
    job.queueableCtx = new AsyncMock.MockQueueableContext();
    job.work();
    // Assert results
}

// Slower - full integration test
@IsTest
static void integrationTest() {
    Test.startTest();
    Async.queueable(new MyJob()).enqueue();
    Test.stopTest();
    // Assert results
}
```

### 4. Test Both Success and Failure Paths

Always verify your jobs handle both outcomes:

```apex
@IsTest
static void shouldHandleSuccess() {
    AsyncMock.whenFinalizer('handler').thenReturn(ParentJobResult.SUCCESS);
    // Test success path
}

@IsTest
static void shouldHandleFailure() {
    AsyncMock.whenFinalizer('handler').thenThrow(new DmlException('Failed'));
    // Test error handling path
}
```

## Summary

AsyncMock enables comprehensive testing of async jobs by providing mock implementations of Salesforce context interfaces. Key capabilities:

| Feature | Benefit |
|---------|---------|
| Mock contexts | Control job behavior in tests |
| Queue-based mocks | Test sequential call patterns |
| Default fallback | Simplify multi-job test setup |
| Direct testing | Faster, focused unit tests |

Use these patterns to ensure your async jobs are thoroughly tested and resilient to both success and failure scenarios.
