public inherited sharing abstract class ChunkJob extends QueueableJob {
    @TestVisible
    private ChunkSource source;
    @TestVisible
    private Integer chunkSize;
    @TestVisible
    private Integer position = 0;
    @TestVisible
    private Integer totalSize;
    @TestVisible
    private Boolean stopRemainingChunksOnFailure = false;
    @TestVisible
    private Integer delayBetweenChunks;
    @TestVisible
    private Boolean keepPages = false;

    public abstract void work(List<SObject> chunk);

    public override void work() {
        Integer count = Math.min(chunkSize, totalSize - position);
        work(source.fetch(position, count));
    }

    public void prepareRun(
        ChunkSource source,
        Integer chunkSize,
        Boolean stopRemainingChunksOnFailure,
        Integer delayBetweenChunks,
        Boolean keepPages
    ) {
        this.source = source;
        this.chunkSize = chunkSize;
        this.stopRemainingChunksOnFailure = stopRemainingChunksOnFailure;
        this.delayBetweenChunks = delayBetweenChunks;
        this.keepPages = keepPages;
        this.position = 0;
        this.totalSize = source.size();
        // Chunk errors are recorded in AsyncResult, not rethrown, so one bad page never aborts the run.
        this.continueOnJobExecuteFail = true;
    }

    public Boolean shouldKeepPages() {
        return keepPages;
    }

    public ChunkJob nextPageOrNull() {
        if (hasFailed && stopRemainingChunksOnFailure) {
            return null;
        }
        Integer nextPosition = position + chunkSize;
        if (nextPosition >= totalSize) {
            return null;
        }
        ChunkJob nextPage = (ChunkJob) this.cloneJob();
        nextPage.position = nextPosition;
        nextPage.delay = delayBetweenChunks;
        nextPage.retryAttempt = 0;
        nextPage.hasFailed = false;
        nextPage.failure = null;
        nextPage.retryDecision = false;
        nextPage.retryHistory = null;
        nextPage.finalizerCtx = null;
        nextPage.isProcessed = false;
        nextPage.resultCreated = false;
        return nextPage;
    }
}
