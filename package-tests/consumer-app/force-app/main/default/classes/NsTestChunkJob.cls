public class NsTestChunkJob extends btcdev.ChunkJob {
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
