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
    }

    public void attachQueueableChainFinalizer() {
        System.attachFinalizer(new QueueableChainFinalizer(this));
    }

    public void executeCurrentJob(QueueableContext ctx) {
        if (!hasNextJob()) {
            return;
        }

        currentJob = getNextJobToProcess();
        currentJob.queueableCtx = ctx;
        currentJob.setChainCounterToName(++chainCounter);
        Savepoint sp = currentJob.rollbackOnJobExecuteFail ? Database.setSavepoint() : null;
        try {
            System.debug(currentJob.customJobId);
            System.debug(currentJob.uniqueName);
            currentJob.work();
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

    public void enqueueNextJobIfAnyFromFinalizer(FinalizerContext ctx) {
        QueueableJob previousJob = currentJob;
        previousJob.isProcessed = true;
        previousJob.finalizerCtx = ctx;
        
        setFinalizerContextToAllFinalizersForPreviousJob(previousJob, ctx);
        enqueueNextJobIfAny();
    }

    public void enqueueNextJobIfAny() {
        if (!hasNextJob() || (Test.isRunningTest() && System.isQueueable())) {
            return;
        }
        
        jobs.sort();
        QueueableJob nextJob = getNextJobToProcess();
        try {
            isChainedContext = true;
            nextJob.enqueue(this);
        } catch (Exception ex) {
            if (!nextJob.continueOnJobEnqueueFail) {
                throw ex;
            }
            isChainedContext = false;
            nextJob.isProcessed = true;
            enqueueNextJobIfAny();
        }
    }

    public Boolean hasNextJob() {
        return getNextJobToProcess() != null;
    }

    public void addJob(QueueableJob job) {
        job.setMainAttributes();
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

    public Boolean isChainedContext() {
        return isChainedContext;
    }

    public Id getQueueableChainBatchId() {
        return initialQueuableChainBatchJobId;
    }

    private QueueableJob getNextJobToProcess() {
        for (QueueableJob job : jobs) {
            if (!job.isProcessed) {
                return job;
            }
        }
        return null;
    }

    private void setFinalizerContextToAllFinalizersForPreviousJob(QueueableJob previousJob, FinalizerContext ctx) {
        for (QueueableJob job : jobs) {
            if (!job.isProcessed && job.parentCustomJobId == previousJob.customJobId && job.finalizerCtx == null) {
                job.finalizerCtx = ctx;
            }
        }
    }
}
