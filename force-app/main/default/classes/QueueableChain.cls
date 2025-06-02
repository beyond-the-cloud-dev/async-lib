public inherited sharing class QueueableChain {
    private List<QueueableJob> jobs = new List<QueueableJob>();
    @TestVisible
    private Id initialQueuableChainBatchJobId;
    private Boolean isChainedContext = false;
    private Integer chainCounter = 0;
    private QueueableJob currentJob;

    public void execute(QueueableContext ctx) {
        QueueableManager.get().setChain(this);
        executeCurrentJob(ctx);
        enqueueNextJobIfAny();
    }

    public void executeCurrentJob(QueueableContext ctx) {
        if (!hasNextJob()) {
            return;
        }

        currentJob = jobs.remove(0);
        System.attachFinalizer(new QueueableChainFinalizer(this));
        currentJob.setChainCounterToName(++chainCounter);
        Savepoint sp = currentJob.rollbackOnJobExecuteFail ? Database.setSavepoint() : null;
        try {
            System.debug(currentJob.uniqueName);
            currentJob.work(ctx);
        } catch (Exception ex) {
            if (!currentJob.continueOnJobExecuteFail) {
                throw ex;
            }
            if (currentJob.rollbackOnJobExecuteFail) {
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
            if (!nextJob.continueOnJobEnqueueFail) {
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
        job.setNames();
        jobs.add(job);
    }

    public void executeOrReplaceInitialQueueableChainBatchJobIfNotInChainContext() {
        if (isChainedContext) {
            return;
        }
        QueueableChainBatch.removeInitialQueuableChainBatchJobIfExists(initialQueuableChainBatchJobId);
        initialQueuableChainBatchJobId = Database.executeBatch(new QueueableChainBatch(this));
    }

    public QueueableJob getCurrentJob() {
        return currentJob;
    }

    public Id getQueueableChainBatchId() {
        return initialQueuableChainBatchJobId;
    }
}
