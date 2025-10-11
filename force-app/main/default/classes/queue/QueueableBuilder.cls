public inherited sharing class QueueableBuilder {
    private QueueableJob job;

    public QueueableBuilder(QueueableJob job) {
        this.job = job;
    }

    public QueueableBuilder asyncOptions(AsyncOptions asyncOptions) {
        if (job.delay != null) {
            throw new IllegalArgumentException(QueueableManager.ERROR_MESSAGE_ASYNC_OPTIONS_AFTER_DELAY);
        }
        job.asyncOptions = asyncOptions;
        return this;
    }

    public QueueableBuilder delay(Integer delay) {
        if (job.asyncOptions != null) {
            throw new IllegalArgumentException(QueueableManager.ERROR_MESSAGE_DELAY_AFTER_ASYNC_OPTIONS);
        }
        job.delay = delay;
        return this;
    }

    public QueueableBuilder priority(Integer priority) {
        job.priority = priority;
        return this;
    }

    public QueueableBuilder continueOnJobEnqueueFail() {
        job.continueOnJobEnqueueFail = true;
        return this;
    }

    public QueueableBuilder continueOnJobExecuteFail() {
        job.continueOnJobExecuteFail = true;
        return this;
    }

    public QueueableBuilder rollbackOnJobExecuteFail() {
        job.rollbackOnJobExecuteFail = true;
        return this;
    }

    public QueueableBuilder chain(QueueableJob job) {
        chain();
        this.job = job;
        return this;
    }

    public SchedulableBuilder asSchedulable() {
        return new SchedulableBuilder(this);
    }

    public Async.Result chain() {
        return QueueableManager.get().chain(job);
    }

    public Async.Result attachFinalizer() {
        return QueueableManager.get().attachFinalizer(job);
    }

    public Async.Result enqueue() {
        chain();
        return QueueableManager.get().enqueue(job);
    }
}
