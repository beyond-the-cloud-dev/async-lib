public inherited sharing class ChunkBuilder {
    @TestVisible
    private static final String ERROR_MESSAGE_INVALID_CHUNK_SIZE = 'chunkSize must be a positive integer';
    @TestVisible
    private static final String ERROR_MESSAGE_NULL_JOB = 'ChunkJob cannot be null';
    @TestVisible
    private static final String ERROR_MESSAGE_NULL_SOURCE = 'ChunkSource cannot be null';
    @TestVisible
    private static final String ERROR_MESSAGE_DEEP_CLONE_UNSUPPORTED = 'deepClone is not supported for a ChunkJob: a Database.Cursor source cannot be JSON-serialized.';
    private static final Integer DEFAULT_CHUNK_SIZE = 200;

    private ChunkJob job;
    private ChunkSource source;
    private Integer chunkSize = DEFAULT_CHUNK_SIZE;
    private Boolean stopRemainingChunksOnFailure = false;
    private Integer delayBetweenChunks;
    private Boolean keepPages = false;

    public ChunkBuilder(ChunkJob job, ChunkSource source) {
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
    }

    public ChunkBuilder chunkSize(Integer chunkSize) {
        if (chunkSize == null || chunkSize <= 0) {
            throw new IllegalArgumentException(ERROR_MESSAGE_INVALID_CHUNK_SIZE);
        }
        this.chunkSize = chunkSize;
        return this;
    }

    public ChunkBuilder stopRemainingChunksOnFailure() {
        this.stopRemainingChunksOnFailure = true;
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

    // Retain settled pages in the chain for introspection instead of pruning them. Off by
    // default; not for large runs, since kept pages grow the serialized chain state.
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

    public Async.Result enqueue() {
        if (source.size() == 0) {
            return new Async.Result((Id) null)
                .setQueueableChainState(
                    new Async.QueueableChainState().setJobs(new List<QueueableJob>())
                );
        }
        job.prepareRun(
            source,
            chunkSize,
            stopRemainingChunksOnFailure,
            delayBetweenChunks,
            keepPages
        );
        return QueueableManager.get().chainAndEnqueue(job);
    }
}
