public inherited sharing abstract class IdChunkJob extends ChunkJob {
    public abstract void work(Set<Id> ids);

    public override void work(List<SObject> chunk) {
        Set<Id> ids = new Set<Id>();
        for (SObject record : chunk) {
            if (record.Id != null) {
                ids.add(record.Id);
            }
        }
        work(ids);
    }
}
