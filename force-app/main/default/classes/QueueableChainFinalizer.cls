public inherited sharing class QueueableChainFinalizer implements Finalizer {
    private QueueableChain chain;

    public QueueableChainFinalizer(QueueableChain chain) {
        if (chain == null) {
            throw new IllegalArgumentException('QueueableChain cannot be null');
        }
        this.chain = chain;
    }

    public void execute(FinalizerContext ctx) {
        chain.enqueueFinalizerOrNextJobIfAnyOnChainFail(ctx);
    }
}
