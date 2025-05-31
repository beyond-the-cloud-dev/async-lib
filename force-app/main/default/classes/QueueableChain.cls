public with sharing class QueueableChain implements Queueable, Database.AllowsCallouts {
    private List<QueueableJob> jobs = new List<QueueableJob>();
    @TestVisible
    private Id initialQueuableChainBatchJobId;
    private Boolean isChainedContext = false;
    private Integer chainCounter = 0;

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
        currentJob.setChainCounterToName(++chainCounter);
        Savepoint sp = currentJob.doNotRollbackDatabaseOnFail ? null : Database.setSavepoint();
        try {
            System.debug(currentJob.uniqueName);
            currentJob.execute(new Async.AsyncContext(ctx, currentJob));
        } catch (Exception ex) {
            if (currentJob.failChainOnJobExecuteFail) {
                throw ex;
            }
            if (!currentJob.doNotRollbackDatabaseOnFail) {
                Database.rollback(sp);
                Database.releaseSavepoint(sp);
            }
        }
    }

    public void enqueueNextJobIfAny() {
        if (!hasNextJob() || (Test.isRunningTest() && System.isQueueable())) {
            return;
        }

        QueueableJob nextJob = jobs.get(0);
        try {
            isChainedContext = true;
            nextJob.enqueue(this);
        } catch (Exception ex) {
            if (nextJob.failChainOnJobEnqueueFail) {
                throw ex;
            }
            isChainedContext = false;
            jobs.remove(0);
            enqueueNextJobIfAny();
        }
    }

    public Boolean hasNextJob() {
        return !jobs.isEmpty();
    }

    public void addJob(QueueableJob job) {
        job.setNames(job);
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
