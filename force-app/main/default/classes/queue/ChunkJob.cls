public inherited sharing abstract class ChunkJob extends QueueableJob {
    @TestVisible
    private ChunkRun run = new ChunkRun();

    public abstract void work(List<SObject> chunk);

    public override void work() {
        work(run.currentPage());
    }

    public ChunkRun getRun() {
        return run;
    }

    public ChunkJob nextPageOrNull() {
        if (!getRun().hasRemainingPages()) {
            return null;
        }
        ChunkJob nextPage = (ChunkJob) this.cloneJob();
        nextPage.run = run.copyForNextPage(hasFailed);
        nextPage.delay = run.delayBetweenChunks;
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
