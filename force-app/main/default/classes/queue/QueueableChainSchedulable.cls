/**
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
