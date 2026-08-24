public inherited sharing class ChunkRun {
    @TestVisible
    private static final String ERROR_MESSAGE_RUN_NOT_STARTED = 'A ChunkJob runs only as part of a chunk run. Start it with Async.chunk(job, source) or Async.queueable(...).chunk(job, source).';

    public ChunkSource source;
    public Integer chunkSize;
    public Integer position = 0;
    public Integer totalSize;
    public Boolean stopRemainingChunksOnFailure = false;
    public Integer delayBetweenChunks;
    public Boolean keepPages = false;
    public String runId;
    public Boolean hasFailedPage = false;

    public void configure(
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
        this.totalSize = source.getNumRecords();
    }

    public List<SObject> currentPage() {
        if (source == null) {
            throw new IllegalArgumentException(ERROR_MESSAGE_RUN_NOT_STARTED);
        }
        return source.fetch(position, Math.min(chunkSize, totalSize - position));
    }

    public Boolean hasRemainingPages() {
        return source != null && position + chunkSize < totalSize;
    }

    public Boolean isHaltedBy(Boolean pageFailed) {
        return stopRemainingChunksOnFailure && (pageFailed || hasFailedPage);
    }

    public ChunkRun copyForNextPage(Boolean pageFailed) {
        ChunkRun nextRun = new ChunkRun();
        nextRun.source = source;
        nextRun.chunkSize = chunkSize;
        nextRun.position = position + chunkSize;
        nextRun.totalSize = totalSize;
        nextRun.stopRemainingChunksOnFailure = stopRemainingChunksOnFailure;
        nextRun.delayBetweenChunks = delayBetweenChunks;
        nextRun.keepPages = keepPages;
        nextRun.runId = runId;
        nextRun.hasFailedPage = hasFailedPage || pageFailed;
        return nextRun;
    }

    public String remainingWorkSummary() {
        return String.format(
            'Chunk run stopped at page {0} of {1}. {2} page(s) and {3} record(s) were not processed.',
            new List<String>{
                String.valueOf(currentPageNumber()),
                String.valueOf(totalPages()),
                String.valueOf(totalPages() - currentPageNumber() + 1),
                String.valueOf(totalSize - position)
            }
        );
    }

    private Integer totalPages() {
        return (totalSize + chunkSize - 1) / chunkSize;
    }

    private Integer currentPageNumber() {
        return position / chunkSize + 1;
    }
}
