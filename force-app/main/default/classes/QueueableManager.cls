public inherited sharing class QueueableManager {
    public static final String QUEUEABLE_JOB_SETTING_ALL = 'All';
    private static final String ERROR_MESSAGE_CHAIN_NULL = 'QueueableChain cannot be null';
    private static final String ERROR_MESSAGE_ASYNC_OPTIONS_AFTER_DELAY = 'Cannot set asyncOptions after delay has been set';
    private static final String ERROR_MESSAGE_DELAY_AFTER_ASYNC_OPTIONS = 'Cannot set delay after asyncOptions has been set';
    private static final String ERROR_MESSAGE_NO_JOB_SET = 'No Queueable job has been set to enqueue';
    private static final String ERROR_MESSAGE_FINALIZER_JOB_NOT_SET = 'No Finalizer job has been set to attach finalizer';
    @TestVisible
    private static final String ERROR_MESSAGE_CANNOT_ATTACH_FINALIZER = 'Cannot attach finalizer when not in a QueueableChain context';
    @TestVisible
    private static final String ERROR_MESSAGE_CANNOT_ENQUEUE_FINALIZER_DIRECTLY = 'Cannot enqueue a QueueableJob.Finalizer directly. Use attachFinalizer() instead.';
    @TestVisible
    private static final String ERROR_MESSAGE_FINALIZER_JOB_MUST_EXTEND_FINALIZER = 'Finalizer job must extend QueueableJob.Finalizer';

    private static QueueableManager instance;

    private QueueableChain chain = new QueueableChain();
    private QueueableJob currentJob;

    // Should only be used by QueueableChain to set the chain in the context
    public void setChain(QueueableChain chain) {
        if (chain == null) {
            throw new Async.IllegalArgumentException(ERROR_MESSAGE_CHAIN_NULL);
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
            throw new Async.IllegalArgumentException(ERROR_MESSAGE_ASYNC_OPTIONS_AFTER_DELAY);
        }
        currentJob.asyncOptions = asyncOptions;
        return this;
    }

    public QueueableManager delay(Integer delay) {
        if (currentJob.asyncOptions != null) {
            throw new Async.IllegalArgumentException(ERROR_MESSAGE_DELAY_AFTER_ASYNC_OPTIONS);
        }
        currentJob.delay = delay;
        return this;
    }

    public QueueableManager priority(Integer priority) {
        currentJob.priority = priority;
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
            throw new Async.IllegalArgumentException(ERROR_MESSAGE_FINALIZER_JOB_NOT_SET);
        }

        if (!chain.isChainedContext()) {
            throw new Async.IllegalArgumentException(ERROR_MESSAGE_CANNOT_ATTACH_FINALIZER);
        }

        QueueableJob currentJobInChainContact = chain.getCurrentJob();
        currentJob.parentCustomJobId = currentJobInChainContact.customJobId;
        
        return enqueue();
    }

    public Async.AsyncResult enqueue() {
        if (currentJob == null) {
            throw new Async.IllegalArgumentException(ERROR_MESSAGE_NO_JOB_SET);
        }
        if (!currentJob.isFinalizer && currentJob instanceof QueueableJob.Finalizer) {
            throw new Async.IllegalArgumentException(ERROR_MESSAGE_CANNOT_ENQUEUE_FINALIZER_DIRECTLY);
        }
        if (currentJob.isFinalizer && !(currentJob instanceof QueueableJob.Finalizer)) {
            throw new Async.IllegalArgumentException(ERROR_MESSAGE_FINALIZER_JOB_MUST_EXTEND_FINALIZER);
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
