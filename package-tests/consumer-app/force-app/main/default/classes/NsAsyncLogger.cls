global class NsAsyncLogger implements btcdev.Async.OnJobEnqueued, btcdev.Async.OnJobSucceeded, btcdev.Async.OnJobFailed, btcdev.Async.OnRetryEnqueued {
    public void onJobEnqueued(btcdev.Async.JobContext ctx) {
        record('ENQUEUED', ctx.className, ctx.info.get('team'));
    }

    public void onJobSucceeded(btcdev.Async.JobContext ctx) {
        record('SUCCEEDED', ctx.className, ctx.info.get('team'));
    }

    public void onJobFailed(btcdev.Async.FailureContext ctx) {
        record('FAILED', ctx.className, String.valueOf(ctx.retryAttempt));
    }

    public void onRetryEnqueued(btcdev.Async.FailureContext ctx) {
        record('RETRY', ctx.className, String.valueOf(ctx.retryAttempt));
    }

    private void record(String event, String className, String detail) {
        insert new Account(Name = 'NS-LOG-' + event, Description = className + '|' + detail);
    }
}
