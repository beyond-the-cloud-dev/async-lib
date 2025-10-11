public inherited sharing class BatchableManager {
    public static final Integer DEFAULT_BATCH_SIZE = 200;

    private static BatchableManager instance;

    public Async.Result execute(BatchableBuilder builder) {
        if (builder == null || builder.job == null) {
            throw new IllegalArgumentException('Batch job must be set.');
        }

        Id jobId = Database.executeBatch(builder.job, builder.scopeSize ?? DEFAULT_BATCH_SIZE);

        return new Async.Result(jobId)
            .setAsyncType(Async.AsyncType.BATCHABLE);
    }

    public static BatchableManager get() {
        if (instance == null) {
            instance = new BatchableManager();
        }
        return instance;
    }
}
