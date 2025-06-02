public abstract class QueueableJob implements Queueable, Database.AllowsCallouts {
    public String className;
    public String uniqueName;
    public Integer delay;
    public AsyncOptions asyncOptions;
    public Finalizer finalizer;
    public Boolean isJobProcessed = false;
    public Boolean isFinalizerProcessed = false;
    public Boolean continueOnJobEnqueueFail = false;
    public Boolean continueOnJobExecuteFail = false;
    public Boolean rollbackOnJobExecuteFail = false;
    public Id jobId;

    private QueueableChain chain;

    public abstract void work(QueueableContext ctx);

    public void execute(QueueableContext ctx) {
        chain.execute(ctx);
    }

    public void enqueue(QueueableChain chain) {
        this.chain = chain;
        if (delay != null) {
            jobId = System.enqueueJob(this, delay);
        } else if (asyncOptions != null) {
            jobId = System.enqueueJob(this, asyncOptions);
        } else {
            jobId = System.enqueueJob(this);
        }
    }

    public void setNames() {
        this.className = getClassName();
        this.uniqueName = className + '::' + System.now().formatGMT('yyyy-MM-dd\'T\'HH:mm:ss.SSSZ');
    }

    public void setChainCounterToName(Integer chainCounter) {
        this.uniqueName = this.uniqueName + '::' + String.valueOf(chainCounter);
    }

    public Boolean isProcessed() {
        return isJobProcessed && isFinalizerProcessed();
    }

    private Boolean isFinalizerProcessed() {
        return finalizer == null || finalizer != null && isFinalizerProcessed;
    }

    private String getClassName() {
        return String.valueOf(this).substringBefore(':');
    }

    public abstract class WithCallouts extends QueueableJob implements Database.AllowsCallouts {
    }
}
