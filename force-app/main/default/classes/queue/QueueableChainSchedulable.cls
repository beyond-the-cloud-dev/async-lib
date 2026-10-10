/**
 * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
 *
 * v3.1.0
 *
 * PMD False Positives:
 * - EmptyCatchBlock: Catch is just for additional safety when creating initial job, and later removing it
 **/
@SuppressWarnings('PMD.EmptyCatchBlock')
public inherited sharing class QueueableChainSchedulable implements Schedulable {
    private QueueableChain chain;

    public QueueableChainSchedulable(QueueableChain chain) {
        if (chain == null) {
            throw new IllegalArgumentException('QueueableChain cannot be null');
        }
        this.chain = chain;
    }

    public void execute(SchedulableContext ctx) {
        chain.enqueueNextJobIfAny();
        System.abortJob(ctx.getTriggerId());
    }

    public static void removeInitialQueuableChainSchedulableIfExists(Id jobId) {
        if (jobId == null) {
            return;
        }

        try {
            System.abortJob(jobId);
        } catch (Exception e) {
            // No action if not exists
        }
    }
}
