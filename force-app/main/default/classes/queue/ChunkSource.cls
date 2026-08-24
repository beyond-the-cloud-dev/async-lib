public inherited sharing abstract class ChunkSource {
    public static final String ERROR_MESSAGE_NULL_CURSOR = 'Database.Cursor cannot be null';
    public static final String ERROR_MESSAGE_BLANK_QUERY = 'SOQL query cannot be blank';

    public abstract Integer getNumRecords();
    public abstract List<SObject> fetch(Integer position, Integer count);

    public virtual Integer maxChunkSize() {
        return null;
    }

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
        assertQueryIsSet(soql);
        return new CursorChunkSource(Database.getCursor(soql));
    }

    public static ChunkSource query(String soql, Map<String, Object> binds) {
        assertQueryIsSet(soql);
        return new CursorChunkSource(
            Database.getCursorWithBinds(soql, binds, AccessLevel.SYSTEM_MODE)
        );
    }

    private static void assertQueryIsSet(String soql) {
        if (String.isBlank(soql)) {
            throw new IllegalArgumentException(ERROR_MESSAGE_BLANK_QUERY);
        }
    }
}
