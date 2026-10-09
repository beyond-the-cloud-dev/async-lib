/**
 * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
 *
 * v3.0.0
 **/
public inherited sharing class QueueableChainFinalizer implements Finalizer {
    private QueueableChain chain;

    public QueueableChainFinalizer(QueueableChain chain) {
        if (chain == null) {
            throw new IllegalArgumentException('QueueableChain cannot be null');
        }
        this.chain = chain;
    }

    // Nothing surfaces a finalizer exception: the parent AsyncApexJob still reads Completed, so a
    // framework fault here would stop the chain with no trace anywhere.
    public void execute(FinalizerContext ctx) {
        try {
            chain.enqueueNextJobIfAnyFromFinalizer(ctx);
        } catch (Exception frameworkFailure) {
            chain.recordFrameworkFailure(frameworkFailure);
            throw frameworkFailure;
        }
    }
}
