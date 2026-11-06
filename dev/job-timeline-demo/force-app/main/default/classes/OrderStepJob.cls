/**
 * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
 *
 * v3.1.0
 **/
public virtual class OrderStepJob extends QueueableJob {
    public Integer spinMs = 1500;
    public override virtual void work() {
        Long until = System.currentTimeMillis() + spinMs;
        while (System.currentTimeMillis() < until) {
        }
    }
}
