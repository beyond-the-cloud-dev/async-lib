public inherited sharing abstract class ChunkSource {
    public static final String ERROR_MESSAGE_NULL_CURSOR = 'Database.Cursor cannot be null';
    public static final String ERROR_MESSAGE_BLANK_QUERY = 'SOQL query cannot be blank';

    public abstract Integer size();
    public abstract List<SObject> fetch(Integer offset, Integer count);

    public static ChunkSource of(List<SObject> records) {
        return new InMemoryChunkSource(records);
    }

    public static ChunkSource ofIds(Set<Id> ids) {
        List<SObject> records = new List<SObject>();
        if (ids != null) {
            for (Id recordId : ids) {
                records.add(recordId.getSObjectType().newSObject(recordId));
            }
        }
        return new InMemoryChunkSource(records);
    }

    public static ChunkSource cursor(Database.Cursor cursor) {
        if (cursor == null) {
            throw new IllegalArgumentException(ERROR_MESSAGE_NULL_CURSOR);
        }
        return new CursorChunkSource(cursor);
    }

    public static ChunkSource query(String soql) {
        if (String.isBlank(soql)) {
            throw new IllegalArgumentException(ERROR_MESSAGE_BLANK_QUERY);
        }
        return new CursorChunkSource(Database.getCursor(soql));
    }

    public class InMemoryChunkSource extends ChunkSource {
        private List<SObject> records;

        private InMemoryChunkSource(List<SObject> records) {
            this.records = records == null ? new List<SObject>() : records;
        }

        public override Integer size() {
            return records.size();
        }

        public override List<SObject> fetch(Integer offset, Integer count) {
            List<SObject> page = new List<SObject>();
            Integer endIndex = Math.min(offset + count, records.size());
            for (Integer i = offset; i < endIndex; i++) {
                page.add(records[i]);
            }
            return page;
        }
    }

    public class CursorChunkSource extends ChunkSource {
        private Database.Cursor cursor;

        private CursorChunkSource(Database.Cursor cursor) {
            this.cursor = cursor;
        }

        public override Integer size() {
            return cursor.getNumRecords();
        }

        public override List<SObject> fetch(Integer offset, Integer count) {
            return cursor.fetch(offset, count);
        }
    }
}
