/**
 * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
 *
 * v3.1.0
 **/
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
