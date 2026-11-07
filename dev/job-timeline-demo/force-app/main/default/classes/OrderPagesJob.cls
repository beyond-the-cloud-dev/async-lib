/**
 * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
 *
 * v3.2.0
 **/
public class OrderPagesJob extends ChunkJob implements Async.ChunkResettable {
    public Integer spinMs = 2500;
    public override void work(List<SObject> page) {
        Long until = System.currentTimeMillis() + spinMs;
        while (System.currentTimeMillis() < until) {
        }
    }
    public void resetBeforeNextChunk(Integer pageNumber) {
    }
}
