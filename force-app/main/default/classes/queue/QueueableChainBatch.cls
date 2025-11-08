/**
 * PMD False Positives:
 * - EmptyCatchBlock: Catch is just for additional safety when creating initial job, and later removing it
 **/
@SuppressWarnings('PMD.EmptyCatchBlock')
public inherited sharing class QueueableChainBatch implements Schedulable, Database.Batchable<sObject> {
    private QueueableChain chain;
    private String cronTriggerId;

    public QueueableChainBatch(QueueableChain chain) {
        if (chain == null) {
            throw new IllegalArgumentException('QueueableChain cannot be null');
        }
        this.chain = chain;
    }

    public void execute(SchedulableContext ctx) {
        this.cronTriggerId = ctx.getTriggerId();
        Database.executeBatch(this, 1);
    }

    public void execute(Database.BatchableContext bc, List<Account> scope) {
        chain.enqueueNextJobIfAny();
    }

    public static void removeInitialQueuableChainBatchJobIfExists(Id jobId) {
        if (jobId == null) {
            return;
        }

        try {
            System.abortJob(jobId);
        } catch (Exception e) {
            // No action if not exists
        }
    }

    public Iterable<Account> start(Database.BatchableContext bc) {
        // This is just a placeholder to start the batch.
        return new List<Account>{ new Account() };
    }

    public void finish(Database.BatchableContext bc) {
        System.abortJob(this.cronTriggerId);
    }
}
