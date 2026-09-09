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

    // ChunkRun holds an abstract ChunkSource, which JSON cannot rebuild. Dropping it keeps the
    // source out of the copy entirely, and carryFrameworkStateFrom puts the live one back.
    protected override void clearFrameworkStateForCopy() {
        run = null;
    }

    protected override void carryFrameworkStateFrom(QueueableJob liveJob) {
        run = ((ChunkJob) liveJob).run;
    }

    public ChunkJob nextPageOrNull() {
        if (!getRun().hasRemainingPages()) {
            return null;
        }
        ChunkJob nextPage = restoreStateOnNextChunk && canRestoreEnqueuedState()
            ? (ChunkJob) this.restoreEnqueuedState()
            : (ChunkJob) this.cloneJob();
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
        if (!restoreStateOnNextChunk && nextPage instanceof Async.ChunkResettable) {
            ((Async.ChunkResettable) nextPage)
                .resetBeforeNextChunk(nextPage.run.currentPageNumber());
        }
        return nextPage;
    }
}
