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
