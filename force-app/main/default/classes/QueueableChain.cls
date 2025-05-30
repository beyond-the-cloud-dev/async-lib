public with sharing class QueueableChain implements Queueable, Database.AllowsCallouts {
    private List<QueueableJob> jobs = new List<QueueableJob>();
    @TestVisible
    private Id initialQueuableChainBatchJobId;
    private Boolean isChainedContext = false;

    public void execute(QueueableContext ctx) {
        QueueableManager.get().setChain(this);
        executeCurrentJob(ctx);
        enqueueNextJobIfAny();
    }

    public void executeCurrentJob(QueueableContext ctx) {
        if (!hasNextJob()) {
            return;
        }

        QueueableJob currentJob = jobs.remove(0);
        Savepoint sp = Database.setSavepoint();
        try {
            System.debug(currentJob.uniqueName);
            currentJob.execute(new Async.AsyncContext(ctx));
        } catch (Exception ex) {
            Database.rollback(sp);
            Database.releaseSavepoint(sp);
        }
    }

    public void initialEnqueueNextJobIfAny() {
        isChainedContext = true;
        enqueueNextJobIfAny();
    }

    public void enqueueNextJobIfAny() {
        if (!hasNextJob() || (Test.isRunningTest() && System.isQueueable())) {
            return;
        }

        QueueableJob nextJob = jobs.get(0);
        try {
            nextJob.enqueue(this);
        } catch (Exception ex) {
            jobs.remove(0);
            enqueueNextJobIfAny();
        }
    }

    public Boolean hasNextJob() {
        return !jobs.isEmpty();
    }

    public void addJob(QueueableJob job) {
        jobs.add(job);
    }

    public void executeOrReplaceInitialQueueableChainBatchJobIfNotInChainContext() {
        if (isChainedContext) {
            return;
        }
        QueueableChainBatch.removeInitialQueuableChainBatchJobIfExists(initialQueuableChainBatchJobId);
        initialQueuableChainBatchJobId = Database.executeBatch(new QueueableChainBatch(this));
    }
}
