/**
 * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
 *
 * v3.1.0
 **/
public inherited sharing class BatchableManager {
    public static final Integer DEFAULT_BATCH_SIZE = 200;

    private static BatchableManager instance;

    public Async.Result execute(BatchableBuilder builder) {
        if (builder == null || builder.job == null) {
            throw new IllegalArgumentException('Batch job must be set.');
        }

        Id jobId = Database.executeBatch(builder.job, builder.scopeSize ?? DEFAULT_BATCH_SIZE);

        return new Async.Result(jobId).setAsyncType(Async.AsyncType.BATCHABLE);
    }

    public static BatchableManager get() {
        if (instance == null) {
            instance = new BatchableManager();
        }
        return instance;
    }
}
