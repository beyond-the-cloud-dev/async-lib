/**
 * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
 *
 * v3.0.0
 **/
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
