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
