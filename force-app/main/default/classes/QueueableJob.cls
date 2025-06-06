public abstract class QueueableJob implements Queueable, Database.AllowsCallouts {
    public String salesforceJobId;
    public String customJobId;
    public String className;
    public String uniqueName;
    public Integer delay;
    public AsyncOptions asyncOptions;
    public Boolean isProcessed = false;
    public Boolean continueOnJobEnqueueFail = false;
    public Boolean continueOnJobExecuteFail = false;
    public Boolean rollbackOnJobExecuteFail = false;
    public QueueableContext queueableCtx;

    public String parentCustomJobId;
    public FinalizerContext finalizerCtx;
    public Boolean isFinalizer {
        get {
            return String.isNotBlank(parentCustomJobId);
        }
    }
    
    private QueueableChain chain;

    public abstract void work();

    public void execute(QueueableContext ctx) {
        chain.execute(ctx);
    }

    public void enqueue(QueueableChain chain) {
        this.chain = chain;
        if (delay != null) {
            salesforceJobId = System.enqueueJob(this, delay);
        } else if (asyncOptions != null) {
            salesforceJobId = System.enqueueJob(this, asyncOptions);
        } else {
            salesforceJobId = System.enqueueJob(this);
        }
    }

    public void setMainAttributes() {
        this.customJobId = UUID.randomUUID().toString();
        this.className = getClassName();
        this.uniqueName = className + '::' + System.now().formatGMT('yyyy-MM-dd\'T\'HH:mm:ss.SSSZ');
    }

    public void setChainCounterToName(Integer chainCounter) {
        this.uniqueName = this.uniqueName + '::' + String.valueOf(chainCounter);
    }

    private String getClassName() {
        return String.valueOf(this).substringBefore(':');
    }

    public abstract class WithCallouts extends QueueableJob implements Database.AllowsCallouts {
    }

    public abstract class Finalizer extends WithCallouts {
    }
}
