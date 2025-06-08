public inherited sharing class QueueableBuilder {
    private QueueableJob job;

    public QueueableBuilder(QueueableJob job) {
        this.job = job;
    }

    public QueueableBuilder asyncOptions(AsyncOptions asyncOptions) {
        if (job.delay != null) {
            throw new Async.IllegalArgumentException(QueueableManager.ERROR_MESSAGE_ASYNC_OPTIONS_AFTER_DELAY);
        }
        job.asyncOptions = asyncOptions;
        return this;
    }

    public QueueableBuilder delay(Integer delay) {
        if (job.asyncOptions != null) {
            throw new Async.IllegalArgumentException(QueueableManager.ERROR_MESSAGE_DELAY_AFTER_ASYNC_OPTIONS);
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

    public SchedulableBuilder asSchedulable() {
        return new SchedulableBuilder(this);
    }

    public Async.AsyncResult attachFinalizer() {
        return QueueableManager.get().attachFinalizer(job);
    }

    public Async.AsyncResult enqueue() {
        return QueueableManager.get().enqueue(job);
    }
}
