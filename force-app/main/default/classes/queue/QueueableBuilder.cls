/**
 * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
 *
 * v3.2.0
 *
 * PMD False Positives:
 * - ExcessivePublicCount: one fluent method per job option
 * - CyclomaticComplexity / CognitiveComplexity: one guard clause per fluent method, and the most
 *   complex member scores 8
 * - EmptyStatementBlock: Apex requires an explicit no-arg constructor once another exists
 **/
@SuppressWarnings(
    'PMD.ExcessivePublicCount,PMD.CyclomaticComplexity,PMD.CognitiveComplexity,PMD.EmptyStatementBlock'
)
public inherited sharing class QueueableBuilder {
    private QueueableJob job;
    private String lastChainedCustomJobId;

    public QueueableBuilder(QueueableJob job) {
        this.job = job.clone();
    }

    public QueueableBuilder(QueueableJob job, String lastChainedCustomJobId) {
        this.job = job.clone();
        this.lastChainedCustomJobId = lastChainedCustomJobId;
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
        if (job.nextInChain) {
            throw new IllegalArgumentException(
                QueueableManager.ERROR_MESSAGE_PRIORITY_WITH_NEXT_IN_CHAIN
            );
        }
        job.priority = priority;
        return this;
    }

    public QueueableBuilder name(String jobName) {
        job.jobName = jobName;
        return this;
    }

    public QueueableBuilder chainName(String chainName) {
        job.chainName = chainName;
        return this;
    }

    public QueueableBuilder linkRecord(SObject record) {
        return linkRecord(record?.Id);
    }

    public QueueableBuilder linkRecord(Id recordId) {
        job.linkRecords(new List<Id>{ recordId });
        return this;
    }

    public QueueableBuilder linkRecords(List<SObject> records) {
        job.linkRecords(QueueableManager.idsOf(records));
        return this;
    }

    public QueueableBuilder linkRecords(List<Id> recordIds) {
        job.linkRecords(recordIds);
        return this;
    }

    public QueueableBuilder linkRecords(Set<Id> recordIds) {
        job.linkRecords(recordIds == null ? null : new List<Id>(recordIds));
        return this;
    }

    public QueueableBuilder linkExternalRecord(String source, String objectName, String key) {
        job.linkExternalRecords(
            new List<Async.RecordLink>{ new Async.RecordLink(source, objectName, key) }
        );
        return this;
    }

    public QueueableBuilder linkExternalRecords(List<Async.RecordLink> links) {
        job.linkExternalRecords(links);
        return this;
    }

    public QueueableBuilder nextInChain() {
        if (job.priority != null) {
            throw new IllegalArgumentException(
                QueueableManager.ERROR_MESSAGE_PRIORITY_WITH_NEXT_IN_CHAIN
            );
        }
        job.nextInChain = true;
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

    public QueueableBuilder restoreStateOnRetry() {
        job.restoreStateOnRetry = true;
        return this;
    }

    public QueueableBuilder deepClone() {
        job.deepClone = true;
        return this;
    }

    public QueueableBuilder retry(Integer maxRetries) {
        QueueableManager.assertValidMaxRetries(maxRetries);
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
        QueueableManager.addRetryOnTypes(job, exceptionTypes);
        return this;
    }

    public QueueableBuilder info(String key, String value) {
        job.info = job.info ?? new Map<String, String>();
        job.info.put(key, value);
        return this;
    }

    public QueueableBuilder info(Map<String, String> info) {
        job.info = job.info ?? new Map<String, String>();
        job.info.putAll(info);
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

    public ChunkBuilder chunk(ChunkJob chunkJob, ChunkSource source) {
        if (this.job != null) {
            lastChainedCustomJobId = chain().customJobId;
            this.job = null;
        }
        return new ChunkBuilder(chunkJob, source, lastChainedCustomJobId);
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
            return QueueableManager.get().enqueueJobsChainedEarlier();
        }
        return QueueableManager.get().chainAndEnqueue(job);
    }
}
