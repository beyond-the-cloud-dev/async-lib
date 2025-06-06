public inherited sharing class QueueableManager {
    private static QueueableManager instance;

    private QueueableChain chain = new QueueableChain();
    private QueueableJob currentJob;

    // Should only be used by QueueableChain to set the chain in the context
    public void setChain(QueueableChain chain) {
        if (chain == null) {
            throw new Async.IllegalArgumentException('QueueableChain cannot be null');
        }
        this.chain = chain;
    }

    public Async.QueueableJobContext getQueueableJobContext() {
        Async.QueueableJobContext ctx = new Async.QueueableJobContext();
        ctx.currentJob = chain.getCurrentJob();
        return ctx;
    }

    public Id getQueueableChainBatchId() {
        return chain.getQueueableChainBatchId();
    }

    public QueueableManager setJob(QueueableJob job) {
        currentJob = job;
        return this;
    }

    public QueueableManager asyncOptions(AsyncOptions asyncOptions) {
        if (currentJob.delay != null) {
            throw new Async.IllegalArgumentException('Cannot set asyncOptions after delay has been set');
        }
        currentJob.asyncOptions = asyncOptions;
        return this;
    }

    public QueueableManager delay(Integer delay) {
        if (currentJob.asyncOptions != null) {
            throw new Async.IllegalArgumentException('Cannot set delay after asyncOptions has been set');
        }
        currentJob.delay = delay;
        return this;
    }

    public QueueableManager continueOnJobEnqueueFail() {
        currentJob.continueOnJobEnqueueFail = true;
        return this;
    }

    public QueueableManager continueOnJobExecuteFail() {
        currentJob.continueOnJobExecuteFail = true;
        return this;
    }

    public QueueableManager rollbackOnJobExecuteFail() {
        currentJob.rollbackOnJobExecuteFail = true;
        return this;
    }

    public Async.AsyncResult attachFinalizer() {
        if (currentJob == null) {
            throw new Async.IllegalArgumentException('No Finalizer job has been set to attach finalizer');
        }

        if (!chain.isChainedContext()) {
            throw new Async.IllegalArgumentException('Cannot attach finalizer when not in a QueueableChain context');
        }

        QueueableJob currentJobInChainContact = chain.getCurrentJob();
        currentJob.parentCustomJobId = currentJobInChainContact.customJobId;
        
        return enqueue();
    }

    public Async.AsyncResult enqueue() {
        if (currentJob == null) {
            throw new Async.IllegalArgumentException('No Queueable job has been set to enqueue');
        }
        if (!currentJob.isFinalizer && currentJob instanceof QueueableJob.Finalizer) {
            throw new Async.IllegalArgumentException('Cannot enqueue a QueueableChain directly. Use attachFinalizer instead.');
        }
        if (currentJob.isFinalizer && !(currentJob instanceof QueueableJob.Finalizer)) {
            throw new Async.IllegalArgumentException('Finalizer job must extend QueueableJob.Finalizer');
        }


        chain.addJob(currentJob);
        if (shouldEnqueueChainJob()) {
            chain.executeOrReplaceInitialQueueableChainBatchJobIfNotInChainContext();
        } else {
            chain.enqueueNextJobIfAny();
            chain = new QueueableChain();
        }

        Async.AsyncResult result = new Async.AsyncResult(currentJob);
        return result;
    }

    private Boolean shouldEnqueueChainJob() {
        return Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs() || 
            currentJob.isFinalizer || 
            System.isQueueable();
    }

    public static QueueableManager get() {
        if (instance == null) {
            instance = new QueueableManager();
        }
        return instance;
    }
}
