/**
 * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
 *
 * v3.2.0
 **/
public class PriorityDemoJob extends QueueableJob {
    public Integer spinMs = 1000;
    public Id addsJobsLinkedTo;
    public override void work() {
        Long until = System.currentTimeMillis() + spinMs;
        while (System.currentTimeMillis() < until) {
        }
        if (addsJobsLinkedTo == null) {
            return;
        }
        Async.queueable(new PriorityDemoJob())
            .name('Urgent, added at runtime')
            .priority(1)
            .linkRecord(addsJobsLinkedTo)
            .enqueue();
        Async.queueable(new PriorityDemoJob())
            .name('Plain, added at runtime')
            .linkRecord(addsJobsLinkedTo)
            .chain();
    }
}
