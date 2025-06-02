public inherited sharing class QueueableChain {
    private List<QueueableJob> jobs = new List<QueueableJob>();
    @TestVisible
    private Id initialQueuableChainBatchJobId;
    private Boolean isChainedContext = false;
    private Integer chainCounter = 0;
    private QueueableJob currentJob;

    public void execute(QueueableContext ctx) {
        QueueableManager.get().setChain(this);
        attachQueueableChainFinalizer();
        executeCurrentJob(ctx);
        enqueueNextJobIfAny();
    }

    public void attachQueueableChainFinalizer() {
        System.attachFinalizer(new QueueableChainFinalizer(this));
    }

    public void executeCurrentJob(QueueableContext ctx) {
        if (!hasNextJob()) {
            return;
        }

        currentJob = getNextJobToProcess();
        currentJob.setChainCounterToName(++chainCounter);
        Savepoint sp = currentJob.rollbackOnJobExecuteFail ? Database.setSavepoint() : null;
        try {
            System.debug(currentJob.uniqueName);
            currentJob.work(ctx);
            currentJob.isJobProcessed = true;
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

    public void enqueueFinalizerOrNextJobIfAnyOnChainFail(FinalizerContext ctx) {
        if (ctx.getResult() == ParentJobResult.SUCCESS || !hasNextJob()) {
            return;
        }

        QueueableJob previousFailedJob = getNextJobToProcess();
        previousFailedJob.isJobProcessed = true;
        enqueueNextJobIfAny();
    }

    public void enqueueNextJobIfAny() {
        if (!hasNextJob() || (Test.isRunningTest() && System.isQueueable())) {
            return;
        }

        QueueableJob nextJob = getNextJobToProcess();
        try {
            isChainedContext = true;
            nextJob.enqueue(this);
        } catch (Exception ex) {
            if (!nextJob.continueOnJobEnqueueFail) {
                throw ex;
            }
            isChainedContext = false;
            nextJob.isJobProcessed = true;
            enqueueNextJobIfAny();
        }
    }

    public Boolean hasNextJob() {
        return getNextJobToProcess() != null;
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

    private QueueableJob getNextJobToProcess() {
        for (QueueableJob job : jobs) {
            if (!job.isProcessed()) {
                return job;
            }
        }
        return null;
    }
}
