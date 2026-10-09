/**
 * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
 *
 * v3.0.0
 **/
public inherited sharing class InMemoryChunkSource extends ChunkSource {
    private List<SObject> records;

    public InMemoryChunkSource(List<SObject> records) {
        this.records = records ?? new List<SObject>();
    }

    public override Integer getNumRecords() {
        return records.size();
    }

    public override List<SObject> fetch(Integer position, Integer count) {
        List<SObject> page = new List<SObject>();
        Integer endIndex = Math.min(position + count, records.size());
        for (Integer i = position; i < endIndex; i++) {
            page.add(records[i]);
        }
        return page;
    }
}
