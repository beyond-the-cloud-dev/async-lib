public virtual class QueueableJob {
    public String className;
    public String uniqueName;
    public Integer delay;
    public AsyncOptions asyncOptions;
    public Queueable job;
    public Boolean failChainOnJobEnqueueFail = false;
    public Boolean failChainOnJobExecuteFail = false;
    public Boolean doNotRollbackDatabaseOnFail = false;

    public QueueableJob() {
        // Default constructor extending class
    }

    public QueueableJob(Queueable job) {
        if (job == null) {
            throw new IllegalArgumentException('Queueable job cannot be null');
        }
        this.job = job;
    }

    public virtual void execute(Async.AsyncContext ctx) {
        job.execute(ctx.qc);
    }

    public void enqueue(QueueableChain chain) {
        if (delay != null) {
            System.enqueueJob(chain, delay);
        } else if (asyncOptions != null) {
            System.enqueueJob(chain, asyncOptions);
        } else {
            System.enqueueJob(chain);
        }
    }

    public void setNames(Object job) {
        this.className = getClassName(job);
        this.uniqueName = className + '::' + System.now().formatGMT('yyyy-MM-dd\'T\'HH:mm:ss.SSSZ');
    }

    public void setChainCounterToName(Integer chainCounter) {
        this.uniqueName = this.uniqueName + '::' + String.valueOf(chainCounter);
    }

    private String getClassName(Object job) {
        return String.valueOf(job).substringBefore(':');
    }
}
