/**
 * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
 *
 * v3.0.0
 **/
public inherited sharing class QueueableSchedulable implements Schedulable {
    public QueueableBuilder builder;

    public QueueableSchedulable(QueueableBuilder builder) {
        this.builder = builder;
    }

    public void execute(SchedulableContext scx) {
        builder.enqueue();
    }
}
