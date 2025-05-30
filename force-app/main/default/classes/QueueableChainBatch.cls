public class QueueableChainBatch implements Database.Batchable<sObject> {
    private QueueableChain chain;

    public QueueableChainBatch(QueueableChain chain) {
        if (chain == null) {
            throw new IllegalArgumentException('QueueableChain cannot be null');
        }
        this.chain = chain;
    }

    public void execute(Database.BatchableContext bc, List<Account> scope){
        chain.initialEnqueueNextJobIfAny();
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

    public Iterable<Account> start(Database.BatchableContext bc){
        // This is just a placeholder to start the batch.
        return new List<Account>{ new Account() };
    }

    public void finish(Database.BatchableContext bc){
    }
}