public class NsTestChunkJob extends btcdev.ChunkJob implements btcdev.Async.ChunkResettable, btcdev.Async.Retryable {
    public void resetBeforeRetry(Integer attempt) {
    }

    public void resetBeforeNextChunk(Integer pageNumber) {
    }

    public String label;

    public NsTestChunkJob(String label) {
        this.label = label;
    }

    public override void work(List<SObject> chunk) {
        List<Account> toUpdate = new List<Account>();
        for (SObject record : chunk) {
            toUpdate.add(new Account(Id = record.Id, Site = label));
        }
        update toUpdate;
    }
}
