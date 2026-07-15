public inherited sharing class QueueableManager {
    public static final String QUEUEABLE_JOB_SETTING_ALL = 'All';
    public static final String STATUS_COMPLETED = 'COMPLETED';
    public static final String STATUS_FAILED = 'FAILED';
    public static final String STATUS_SKIPPED_DEPENDENCY = 'SKIPPED_DEPENDENCY';
    public static final String STATUS_SKIPPED_CHAIN_STOPPED = 'SKIPPED_CHAIN_STOPPED';
    public static final String STATUS_SKIPPED_EXPLICIT = 'SKIPPED_EXPLICIT';
    public static final String STATUS_SKIPPED_DISABLED = 'SKIPPED_DISABLED';
    public static final Integer MAX_RETRY_CAP = 10;
    public static final String ERROR_MESSAGE_INVALID_MAX_RETRIES = 'Max retries must be a non-negative integer';
    public static final String ERROR_MESSAGE_MAX_RETRIES_EXCEEDS_CAP =
        'Max retries cannot exceed the framework cap of ' + MAX_RETRY_CAP;
    public static final String ERROR_MESSAGE_INVALID_DEPENDENCY = 'A dependency requires a target and an outcome (e.g. Async.after(result).succeeded())';
    public static final String ERROR_MESSAGE_DEPENDS_ON_PREVIOUS_WITHOUT_JOB = 'dependsOn(Async.afterPrevious()) requires a previously chained job';
    public static final String ERROR_MESSAGE_UNKNOWN_JOB = 'No job in this chain has custom job id "{0}".';
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

    public void stopChain() {
        chain.stop();
    }

    public void skipJob(String customJobId) {
        chain.skipJobByCustomJobId(customJobId);
    }

    public Async.QueueableJobContext getQueueableJobContext() {
        Async.QueueableJobContext ctx = new Async.QueueableJobContext();
        ctx.currentJob = chain.getCurrentJob();
        return ctx;
    }

    public Id getQueueableChainSchedulableId() {
        return chain.getQueueableChainSchedulableId();
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

    public Async.Result chainAndEnqueue(QueueableJob job) {
        Async.Result result = chain(job);
        return enqueue(result.job);
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

        QueueableJob clonedJob = job.cloneJob();
        chain.addJob(clonedJob);
        return new Async.Result(clonedJob).setCurrentQueueableChainState();
    }

    public Async.Result enqueue(QueueableJob job) {
        Async.QueueableChainState queueableChainState = new Async.QueueableChainState()
            .setJobs(chain.getJobs())
            .setNextCustomJobIdFromFirstJob();

        Id enqueuedJobId;

        if (shouldExecuteOrReplaceInitialQueueableChainSchedulable()) {
            chain.executeOrReplaceInitialQueueableChainSchedulableJob();
            enqueuedJobId = chain.getQueueableChainSchedulableId();
            queueableChainState
                .setNextSalesforceJobId(enqueuedJobId)
                .setEnqueueType(EnqueueType.INITIAL_QUEUEABLE_CHAIN_SCHEDULABLE);
        } else if (!chain.isChainedContext()) {
            chain.enqueueNextJobIfAny();
            queueableChainState
                .setNextSalesforceJobIdFromFirstJob()
                .setEnqueueType(EnqueueType.NEW_CHAIN);
            List<QueueableJob> jobsAfterEnqueue = chain.getJobs();
            if (jobsAfterEnqueue != null && !jobsAfterEnqueue.isEmpty()) {
                enqueuedJobId = jobsAfterEnqueue.get(0).salesforceJobId;
            }
            chain = new QueueableChain();
        } else {
            queueableChainState.setEnqueueType(EnqueueType.EXISTING_CHAIN);
            enqueuedJobId = job.salesforceJobId;
        }

        Async.Result result = new Async.Result(job).setQueueableChainState(queueableChainState);
        if (enqueuedJobId != null) {
            result.salesforceJobId = enqueuedJobId;
        }
        return result;
    }

    private Boolean shouldExecuteOrReplaceInitialQueueableChainSchedulable() {
        return !chain.isChainedContext() &&
            (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs() || System.isQueueable());
    }

    public static void assertValidMaxRetries(Integer maxRetries) {
        if (maxRetries == null || maxRetries < 0) {
            throw new IllegalArgumentException(ERROR_MESSAGE_INVALID_MAX_RETRIES);
        }
        if (maxRetries > MAX_RETRY_CAP) {
            throw new IllegalArgumentException(ERROR_MESSAGE_MAX_RETRIES_EXCEEDS_CAP);
        }
    }

    public static void addRetryOnTypes(QueueableJob job, List<Type> exceptionTypes) {
        if (job.retryOnExceptionTypes == null) {
            job.retryOnExceptionTypes = new Set<String>();
        }
        for (Type exceptionType : exceptionTypes) {
            if (exceptionType != null) {
                job.retryOnExceptionTypes.add(exceptionType.getName());
            }
        }
    }

    public static QueueableManager get() {
        if (instance == null) {
            instance = new QueueableManager();
        }
        return instance;
    }

    public enum EnqueueType {
        INITIAL_QUEUEABLE_CHAIN_SCHEDULABLE,
        NEW_CHAIN,
        EXISTING_CHAIN
    }
}
