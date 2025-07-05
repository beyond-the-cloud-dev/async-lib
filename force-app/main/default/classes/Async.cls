/**
 * Copyright (c) 2025 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/soql-lib/blob/main/LICENSE)
**/
public inherited sharing class Async {
    // public interface QueueableBuilder {
    //     QueueableBuilder asyncOptions(AsyncOptions asyncOptions);
    //     QueueableBuilder delay(Integer delay);
    //     QueueableBuilder priority(Integer priority);
    //     QueueableBuilder continueOnJobEnqueueFail();
    //     QueueableBuilder continueOnJobExecuteFail();
    //     QueueableBuilder rollbackOnJobExecuteFail();
    //     SchedulableBuilder asSchedulable();
    //     AsyncResult attachFinalizer();
    //     AsyncResult enqueue();
    // }

    public interface BatchableBuilder {
        BatchableBuilder scopeSize(Integer scopeSize);
        BatchableBuilder minutesFromNow(Integer minutes);
        SchedulableBuilder asSchedulable();
        AsyncResult execute();

    }

    // public interface SchedulableBuilder {
    //     SchedulableBuilder name(String name);
    //     SchedulableBuilder cronExpression(String cronExpression);
    //     SchedulableBuilder cronExpression(CronBuilder builder);
    //     SchedulableBuilder cronExpression(List<CronBuilder> builders);
    //     List<AsyncResult> schedule();
    // }

    private static final Integer DEFAULT_BATCH_SIZE = 200;
    private static BatchableManager BATCHABLE_MANAGER_INSTANCE = new BatchableManager();

    public static QueueableBuilder queueable(QueueableJob job) {
        return new QueueableBuilder(job);
    }

    // Object is passed here, since Apex has issues with casting the Database.Batchable<Object> type
    public static BatchableBuilder batchable(Object job) {
        return new AsyncBatchableBuilder(job); 
    }

    public static SchedulableBuilder schedulable(Schedulable scheduleJob) {
        return new SchedulableBuilder(scheduleJob);
    }

    public static QueueableJobContext getQueueableJobContext() {
        return QueueableManager.get()
            .getQueueableJobContext();
    }

    public static Id getQueueableChainBatchId() {
        return QueueableManager.get()
            .getQueueableChainBatchId();
    }

    public class QueueableJobContext {
        public QueueableJob currentJob;
        public QueueableContext queueableCtx {
            get {
                return currentJob.queueableCtx;
            }
        }
        public FinalizerContext finalizerCtx {
            get {
                return currentJob.finalizerCtx;
            }
        }
    }

    public class AsyncResult {
        public Id salesforceJobId;
        public String customJobId;
        public Boolean isChained;

        public AsyncResult(Id salesforceJobId) {
            this.salesforceJobId = salesforceJobId;
        }

        public AsyncResult(QueueableJob job) {
            this.salesforceJobId = job.salesforceJobId;
            this.customJobId = job.customJobId;
            this.isChained = String.isBlank(salesforceJobId);
        }
    }

    public class AsyncBatchableBuilder implements BatchableBuilder {
        public Database.Batchable<Object> job;
        public Integer scopeSize;
        public Integer minutesFromNow;

        public AsyncBatchableBuilder(Object job) {
            this.job = (Database.Batchable<Object>) job;
        }

        public BatchableBuilder scopeSize(Integer scopeSize) {
            if (scopeSize <= 0) {
                throw new IllegalArgumentException('Scope size must be greater than zero.');
            }
            this.scopeSize = scopeSize;
            return this;
        }

        public BatchableBuilder minutesFromNow(Integer minutes) {
            if (minutes <= 0) {
                throw new IllegalArgumentException('Minutes from now must be greater than zero.');
            }
            this.minutesFromNow = minutes;
            return this;
        }

        public SchedulableBuilder asSchedulable() {
            return new SchedulableBuilder(this);
        }

        public AsyncResult execute() {
            return BATCHABLE_MANAGER_INSTANCE.execute(this);
        }
    }

    public class BatchableManager {
        public AsyncResult execute(AsyncBatchableBuilder builder) {
            if (builder == null || builder.job == null) {
                throw new IllegalArgumentException('Batch job must be set.');
            }

            Id jobId = Database.executeBatch(builder.job, builder.scopeSize ?? DEFAULT_BATCH_SIZE);

            AsyncResult result = new AsyncResult(jobId);
            return result;
        }
    }

    public class BatchableSchedulable implements Schedulable {
        public BatchableBuilder builder;
        
        public BatchableSchedulable(BatchableBuilder builder) {
            this.builder = builder;
        }

        public void execute(SchedulableContext scx) {
            builder.execute();
        }
    }
}
