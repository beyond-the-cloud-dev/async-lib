/**
 * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
 *
 * v3.1.0
 **/
public class RepriceLinesJob extends ChunkJob implements Async.ChunkResettable {
    public override void work(List<SObject> page) {
        if (getRun().currentPageNumber() == 5) {
            throw new DmlException('FIELD_CUSTOM_VALIDATION_EXCEPTION: Discount cannot exceed 40%');
        }
    }
    public void resetBeforeNextChunk(Integer pageNumber) {
    }
}
