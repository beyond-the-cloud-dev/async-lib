/**
 * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
 *
 * v3.0.0
 **/
public inherited sharing class BatchableBuilder {
    public Database.Batchable<Object> job;
    public Integer scopeSize;
    public Integer minutesFromNow;

    public BatchableBuilder(Object job) {
        this.job = (Database.Batchable<Object>) job;
    }

    public BatchableBuilder scopeSize(Integer scopeSize) {
        if (scopeSize <= 0) {
            throw new IllegalArgumentException('Scope size must be greater than zero.');
        }
        this.scopeSize = scopeSize;
        return this;
    }

    public BatchableBuilder minutesFromNow(Integer minutes) {
        if (minutes <= 0) {
            throw new IllegalArgumentException('Minutes from now must be greater than zero.');
        }
        this.minutesFromNow = minutes;
        return this;
    }

    public SchedulableBuilder asSchedulable() {
        return new SchedulableBuilder(this);
    }

    public Async.Result execute() {
        return BatchableManager.get().execute(this);
    }
}
