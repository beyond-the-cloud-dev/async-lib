public inherited sharing class QueueableManager {
    public static final String QUEUEABLE_JOB_SETTING_ALL = 'All';
    public static final String ERROR_MESSAGE_ASYNC_OPTIONS_AFTER_DELAY = 'Cannot set asyncOptions after delay has been set';
    public static final String ERROR_MESSAGE_DELAY_AFTER_ASYNC_OPTIONS = 'Cannot set delay after asyncOptions has been set';
    private static final String ERROR_MESSAGE_CHAIN_NULL = 'QueueableChain cannot be null';
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

    // Should only be used by QueueableChain to set the chain in the context
    public void setChain(QueueableChain chain) {
        if (chain == null) {
            throw new IllegalArgumentException(ERROR_MESSAGE_CHAIN_NULL);
        }
        this.chain = chain;
    }
    
    public QueueableChain getChain() {
        return chain;
    }

    public Async.QueueableJobContext getQueueableJobContext() {
        Async.QueueableJobContext ctx = new Async.QueueableJobContext();
        ctx.currentJob = chain.getCurrentJob();
        return ctx;
    }

    public Id getQueueableChainBatchId() {
        return chain.getQueueableChainBatchId();
    }

    public Async.Result attachFinalizer(QueueableJob job) {
        if (job == null) {
            throw new IllegalArgumentException(ERROR_MESSAGE_FINALIZER_JOB_NOT_SET);
        }

        if (!chain.isChainedContext()) {
            throw new IllegalArgumentException(ERROR_MESSAGE_CANNOT_ATTACH_FINALIZER);
        }

        QueueableJob currentJobInChainContact = chain.getCurrentJob();
        job.parentCustomJobId = currentJobInChainContact.customJobId;
        
        return chain(job);
    }

    public Async.Result chain(QueueableJob job) {
        if (job == null) {
            throw new IllegalArgumentException(ERROR_MESSAGE_NO_JOB_SET);
        }
        if (!job.isFinalizer && job instanceof QueueableJob.Finalizer) {
            throw new IllegalArgumentException(ERROR_MESSAGE_CANNOT_ENQUEUE_FINALIZER_DIRECTLY);
        }
        if (job.isFinalizer && !(job instanceof QueueableJob.Finalizer)) {
            throw new IllegalArgumentException(ERROR_MESSAGE_FINALIZER_JOB_MUST_EXTEND_FINALIZER);
        }

        chain.addJob(job);
        return new Async.Result(job)
            .setCurrentQueueableChainState();
    }

    public Async.Result enqueue(QueueableJob job) {
        Async.QueueableChainState queueableChainState = new Async.QueueableChainState()
            .setJobs(chain.getJobs())
            .setNextCustomJobIdFromFirstJob();

        if (shouldExecuteOrReplaceInitialQueueableChainBatch()) {
            chain.executeOrReplaceInitialQueueableChainBatchJob();
            queueableChainState
                .setNextSalesforceJobId(chain.getQueueableChainBatchId())
                .setEnqueueType(EnqueueType.INITIAL_SCHEDULED_BATCH_JOB);
        } else if (!chain.isChainedContext()) {
            chain.enqueueNextJobIfAny();
            queueableChainState
                .setNextSalesforceJobIdFromFirstJob()
                .setEnqueueType(EnqueueType.NEW_CHAIN);
            chain = new QueueableChain();
        } else {
            queueableChainState
                .setEnqueueType(EnqueueType.EXISTING_CHAIN);
        }
        
        return new Async.Result(job)
            .setQueueableChainState(queueableChainState);
    }

    private Boolean shouldExecuteOrReplaceInitialQueueableChainBatch() {
        return 
            !chain.isChainedContext() && (
                Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs() ||
                System.isQueueable()
            );
    }

    public static QueueableManager get() {
        if (instance == null) {
            instance = new QueueableManager();
        }
        return instance;
    }

    public enum EnqueueType {
        INITIAL_SCHEDULED_BATCH_JOB,
        NEW_CHAIN,
        EXISTING_CHAIN
    }
}
