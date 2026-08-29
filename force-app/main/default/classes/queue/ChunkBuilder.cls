public inherited sharing class ChunkBuilder {
    @TestVisible
    private static final String ERROR_MESSAGE_INVALID_CHUNK_SIZE = 'chunkSize must be a positive integer';
    @TestVisible
    private static final String ERROR_MESSAGE_CHUNK_SIZE_ABOVE_SOURCE_MAX = 'chunkSize must be between 1 and {0} for this source';
    @TestVisible
    private static final String ERROR_MESSAGE_NULL_JOB = 'ChunkJob cannot be null';
    @TestVisible
    private static final String ERROR_MESSAGE_NULL_SOURCE = 'ChunkSource cannot be null';
    @TestVisible
    private static final String ERROR_MESSAGE_DEEP_CLONE_UNSUPPORTED = 'deepClone is not supported for a ChunkJob: a Database.Cursor source cannot be JSON-serialized.';
    private static final Integer DEFAULT_CHUNK_SIZE = 200;

    private ChunkJob job;
    private ChunkSource source;
    private String lastChainedCustomJobId;
    private Integer chunkSize = DEFAULT_CHUNK_SIZE;
    private Boolean stopRemainingChunksOnFailure = false;
    private Integer delayBetweenChunks;
    private Boolean keepPages = false;

    public ChunkBuilder(ChunkJob job, ChunkSource source) {
        this(job, source, null);
    }

    public ChunkBuilder(ChunkJob job, ChunkSource source, String lastChainedCustomJobId) {
        if (job == null) {
            throw new IllegalArgumentException(ERROR_MESSAGE_NULL_JOB);
        }
        if (source == null) {
            throw new IllegalArgumentException(ERROR_MESSAGE_NULL_SOURCE);
        }
        if (job.deepClone) {
            throw new IllegalArgumentException(ERROR_MESSAGE_DEEP_CLONE_UNSUPPORTED);
        }
        this.job = (ChunkJob) job.clone();
        this.source = source;
        this.lastChainedCustomJobId = lastChainedCustomJobId;
    }

    public ChunkBuilder chunkSize(Integer chunkSize) {
        if (chunkSize == null || chunkSize <= 0) {
            throw new IllegalArgumentException(ERROR_MESSAGE_INVALID_CHUNK_SIZE);
        }
        Integer sourceMax = source.maxChunkSize();
        if (sourceMax != null && chunkSize > sourceMax) {
            throw new IllegalArgumentException(
                String.format(
                    ERROR_MESSAGE_CHUNK_SIZE_ABOVE_SOURCE_MAX,
                    new List<String>{ String.valueOf(sourceMax) }
                )
            );
        }
        this.chunkSize = chunkSize;
        return this;
    }

    public ChunkBuilder stopRemainingChunksOnFailure() {
        this.stopRemainingChunksOnFailure = true;
        return this;
    }

    public ChunkBuilder dependsOn(Async.Dependency dependency) {
        if (dependency == null || dependency.requiredOutcome == null) {
            throw new IllegalArgumentException(QueueableManager.ERROR_MESSAGE_INVALID_DEPENDENCY);
        }
        if (dependency.previous) {
            if (lastChainedCustomJobId == null) {
                throw new IllegalArgumentException(
                    QueueableManager.ERROR_MESSAGE_DEPENDS_ON_PREVIOUS_WITHOUT_JOB
                );
            }
            dependency.resolvedTargetCustomJobId = lastChainedCustomJobId;
        }
        if (job.dependencies == null) {
            job.dependencies = new List<Async.Dependency>();
        }
        job.dependencies.add(dependency);
        return this;
    }

    public ChunkBuilder priority(Integer priority) {
        job.priority = priority;
        return this;
    }

    public ChunkBuilder delay(Integer delay) {
        job.delay = delay;
        return this;
    }

    public ChunkBuilder delayBetweenChunks(Integer minutes) {
        this.delayBetweenChunks = minutes;
        return this;
    }

    public ChunkBuilder keepChunkPages() {
        this.keepPages = true;
        return this;
    }

    public ChunkBuilder retry(Integer maxRetries) {
        QueueableManager.assertValidMaxRetries(maxRetries);
        job.maxRetries = maxRetries;
        return this;
    }

    public ChunkBuilder backoff(Backoff backoff) {
        job.backoff = backoff;
        return this;
    }

    public ChunkBuilder retryOn(Type exceptionType) {
        return retryOn(new List<Type>{ exceptionType });
    }

    public ChunkBuilder retryOn(List<Type> exceptionTypes) {
        QueueableManager.addRetryOnTypes(job, exceptionTypes);
        return this;
    }

    public ChunkBuilder mockId(String mockId) {
        job.mockId = mockId;
        return this;
    }

    public QueueableBuilder chain(QueueableJob nextJob) {
        Async.Result runResult = chainRun();
        return new QueueableBuilder(nextJob, runResult?.customJobId);
    }

    public ChunkBuilder chunk(ChunkJob nextChunkJob, ChunkSource nextSource) {
        Async.Result runResult = chainRun();
        return new ChunkBuilder(nextChunkJob, nextSource, runResult?.customJobId);
    }

    public Async.Result chain() {
        Async.Result runResult = chainRun();
        return runResult ?? emptyRunResult();
    }

    public Async.Result enqueue() {
        Async.Result runResult = chainRun();
        if (runResult != null) {
            return QueueableManager.get().enqueue(runResult.job);
        }
        List<QueueableJob> alreadyChainedJobs = QueueableManager.get().getChain().getJobs();
        return alreadyChainedJobs.isEmpty()
            ? emptyRunResult()
            : QueueableManager.get().enqueue(alreadyChainedJobs[0]);
    }

    private Async.Result chainRun() {
        if (source.getNumRecords() == 0) {
            return null;
        }
        job.getRun()
            .configure(
                source,
                chunkSize,
                stopRemainingChunksOnFailure,
                delayBetweenChunks,
                keepPages
            );
        recordPageFailuresInsteadOfRethrowing();
        return QueueableManager.get().chain(job);
    }

    private void recordPageFailuresInsteadOfRethrowing() {
        job.continueOnJobExecuteFail = true;
    }

    private Async.Result emptyRunResult() {
        return new Async.Result((Id) null)
            .setQueueableChainState(
                new Async.QueueableChainState().setJobs(new List<QueueableJob>())
            );
    }
}
