/**
 * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
 *
 * v3.0.0
 **/
// A Schedulable entry point with no sharing declaration runs in system mode. `inherited sharing`
// would resolve to `with sharing` here and change how the scheduled batch sees data.
public without sharing class BatchableSchedulable implements Schedulable {
    public BatchableBuilder builder;

    public BatchableSchedulable(BatchableBuilder builder) {
        this.builder = builder;
    }

    public void execute(SchedulableContext scx) {
        builder.execute();
    }
}
