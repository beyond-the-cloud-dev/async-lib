public inherited sharing class QueueableBuilder {
    private QueueableJob job;
    private String lastChainedCustomJobId;

    public QueueableBuilder(QueueableJob job) {
        this.job = job.clone();
    }

    public QueueableBuilder() {
    }

    public QueueableBuilder dependsOn(Async.Dependency dependency) {
        if (dependency == null || dependency.requiredOutcome == null) {
            throw new IllegalArgumentException(QueueableManager.ERROR_MESSAGE_INVALID_DEPENDENCY);
        }
        if (dependency.previous) {
            if (lastChainedCustomJobId == null) {
                throw new IllegalArgumentException(
                    QueueableManager.ERROR_MESSAGE_DEPENDS_ON_PREVIOUS_WITHOUT_JOB
                );
            }
            dependency.resolvedTargetCustomJobId = lastChainedCustomJobId;
        }
        if (job.dependencies == null) {
            job.dependencies = new List<Async.Dependency>();
        }
        job.dependencies.add(dependency);
        return this;
    }

    public QueueableBuilder asyncOptions(AsyncOptions asyncOptions) {
        if (job.delay != null) {
            throw new IllegalArgumentException(
                QueueableManager.ERROR_MESSAGE_ASYNC_OPTIONS_AFTER_DELAY
            );
        }
        job.asyncOptions = asyncOptions;
        return this;
    }

    public QueueableBuilder delay(Integer delay) {
        if (job.asyncOptions != null) {
            throw new IllegalArgumentException(
                QueueableManager.ERROR_MESSAGE_DELAY_AFTER_ASYNC_OPTIONS
            );
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

    // Clones job with all complex class members, removing all references from original job
    // Stored on job, for further reference
    public QueueableBuilder deepClone() {
        job.deepClone = true;
        return this;
    }

    public QueueableBuilder retry(Integer maxRetries) {
        if (maxRetries == null || maxRetries < 0) {
            throw new IllegalArgumentException(QueueableManager.ERROR_MESSAGE_INVALID_MAX_RETRIES);
        }
        if (maxRetries > QueueableManager.MAX_RETRY_CAP) {
            throw new IllegalArgumentException(
                QueueableManager.ERROR_MESSAGE_MAX_RETRIES_EXCEEDS_CAP
            );
        }
        job.maxRetries = maxRetries;
        return this;
    }

    public QueueableBuilder backoff(Backoff backoff) {
        job.backoff = backoff;
        return this;
    }

    public QueueableBuilder retryOn(Type exceptionType) {
        return retryOn(new List<Type>{ exceptionType });
    }

    public QueueableBuilder retryOn(List<Type> exceptionTypes) {
        if (job.retryOnExceptionTypes == null) {
            job.retryOnExceptionTypes = new Set<String>();
        }
        for (Type exceptionType : exceptionTypes) {
            if (exceptionType != null) {
                job.retryOnExceptionTypes.add(exceptionType.getName());
            }
        }
        return this;
    }

    public QueueableBuilder mockId(String mockId) {
        job.mockId = mockId;
        return this;
    }

    public QueueableBuilder chain(QueueableJob job) {
        if (this.job != null) {
            lastChainedCustomJobId = chain().customJobId;
        }
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
        if (this.job == null) {
            return new Async.Result((Id) null)
                .setQueueableChainState(
                    new Async.QueueableChainState().setJobs(new List<QueueableJob>())
                );
        }
        return QueueableManager.get().chainAndEnqueue(job);
    }
}
