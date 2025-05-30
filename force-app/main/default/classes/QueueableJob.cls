public virtual class QueueableJob {
    public String className;
    public String uniqueName;
    public Integer delay;
    public AsyncOptions asyncOptions;
    public Queueable job;

    public QueueableJob(Queueable job) {
        if (job == null) {
            throw new IllegalArgumentException('Queueable job cannot be null');
        }
        this.job = job;
        this.className = getClassName();
        this.uniqueName = className + '::' + System.now().format();
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

    private String getClassName() {
        return String.valueOf(job).substringBefore(':');
    }
}
