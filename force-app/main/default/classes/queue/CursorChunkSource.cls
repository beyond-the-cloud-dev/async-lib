public inherited sharing class CursorChunkSource extends ChunkSource {
    private static final Integer MAX_CURSOR_FETCH_SIZE = 2000;

    private Database.Cursor cursor;

    public CursorChunkSource(Database.Cursor cursor) {
        this.cursor = cursor;
    }

    public override Integer getNumRecords() {
        return cursor.getNumRecords();
    }

    public override List<SObject> fetch(Integer position, Integer count) {
        return cursor.fetch(position, count);
    }

    public override Integer maxChunkSize() {
        return MAX_CURSOR_FETCH_SIZE;
    }
}
