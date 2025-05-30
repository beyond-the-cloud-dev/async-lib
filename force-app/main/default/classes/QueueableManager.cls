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

    public QueueableManager setJob(Queueable job) {
        if (job == null) {
            throw new Async.IllegalArgumentException('Queueable job cannot be null');
        }
        currentJob = new QueueableJob(job);
        return this;
    }

    public QueueableManager setJob(QueueableJob job) {
        if (job == null) {
            throw new Async.IllegalArgumentException('Queueable job cannot be null');
        }
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

    public QueueableManager enqueue() {
        if (currentJob == null) {
            throw new Async.IllegalArgumentException('No Queueable job has been set to enqueue');
        }


        chain.addJob(currentJob);
        if (shouldEnqueueChainJob()) {
            chain.executeOrReplaceInitialQueueableChainBatchJobIfNotInChainContext();
        } else {
            chain.enqueueNextJobIfAny();
            chain = new QueueableChain();
        }
        return this;
    }

    private Boolean shouldEnqueueChainJob() {
        return Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs() || 
            System.isQueueable();
    }

    public static QueueableManager get() {
        if (instance == null) {
            instance = new QueueableManager();
        }
        return instance;
    }
}
