public abstract class QueueableJob implements Queueable, Database.AllowsCallouts {
    public String className;
    public String uniqueName;
    public Integer delay;
    public AsyncOptions asyncOptions;
    public Boolean failChainOnJobEnqueueFail = false;
    public Boolean failChainOnJobExecuteFail = false;
    public Boolean doNotRollbackDatabaseOnFail = false;

    private QueueableChain chain;

    public abstract void work(QueueableContext ctx);

    public void execute(QueueableContext ctx) {
        chain.execute(ctx);
    }

    public void enqueue(QueueableChain chain) {
        this.chain = chain;
        if (delay != null) {
            System.enqueueJob(this, delay);
        } else if (asyncOptions != null) {
            System.enqueueJob(this, asyncOptions);
        } else {
            System.enqueueJob(this);
        }
    }

    public void setNames() {
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
}
