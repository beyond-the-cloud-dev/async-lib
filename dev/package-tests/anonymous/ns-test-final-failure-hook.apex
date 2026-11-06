String marker = 'NsHook-' + String.valueOf(Crypto.getRandomInteger()).right(6);

public class HookJob extends btcdev.QueueableJob {
    public String marker;

    public HookJob(String marker) {
        this.marker = marker;
    }

    public override void work() {
        throw new System.CalloutException('ns hook failure');
    }

    public override void onFinalFailure(btcdev.Async.FailureContext failureCtx) {
        insert new Account(
            Name = marker,
            Description = failureCtx.retryOutcome.name() +
                '|' +
                failureCtx.failure.type +
                '|' +
                (String.isBlank(failureCtx.failure.stackTrace) ? 'NO-TRACE' : 'HAS-TRACE')
        );
    }
}

btcdev.Async.queueable(new HookJob(marker)).continueOnJobExecuteFail().enqueue();

System.assertEquals(
    btcdev.Async.RetryOutcome.NOT_CONFIGURED,
    btcdev.Async.RetryOutcome.valueOf('NOT_CONFIGURED'),
    'RetryOutcome must be reachable from a consumer namespace'
);

System.debug('PASS: ns-test-final-failure-hook (marker ' + marker + ')');
