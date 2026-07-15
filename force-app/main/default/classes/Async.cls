public inherited sharing class Async {
    public static QueueableBuilder queueable(QueueableJob job) {
        return new QueueableBuilder(job);
    }

    public static QueueableBuilder queueable() {
        return new QueueableBuilder();
    }

    public static ChunkBuilder chunk(ChunkJob job, ChunkSource source) {
        return new ChunkBuilder(job, source);
    }

    public static BatchableBuilder batchable(Object job) {
        return new BatchableBuilder(job);
    }

    public static SchedulableBuilder schedulable(Schedulable scheduleJob) {
        return new SchedulableBuilder(scheduleJob);
    }

    public static Dependency after(String customJobId) {
        return new Dependency().onCustomJobId(customJobId);
    }

    public static Dependency after(Result dependency) {
        return new Dependency().onCustomJobId(dependency?.customJobId);
    }

    public static Dependency afterPrevious() {
        return new Dependency().onPrevious();
    }

    public static QueueableJobContext getQueueableJobContext() {
        return QueueableManager.get().getQueueableJobContext();
    }

    public static Id getQueueableChainSchedulableId() {
        return QueueableManager.get().getQueueableChainSchedulableId();
    }

    public static QueueableChainState getCurrentQueueableChainState() {
        return new QueueableChainState().setCurrentQueueableChainState();
    }

    public static void stopChain() {
        QueueableManager.get().stopChain();
    }

    public static void skipJob(String customJobId) {
        QueueableManager.get().skipJob(customJobId);
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

    public class Result {
        public Id salesforceJobId;
        public AsyncType asyncType;
        public String customJobId;
        public QueueableChainState queueableChainState;
        public QueueableJob job;

        public Result(Id salesforceJobId) {
            this.salesforceJobId = salesforceJobId;
        }

        public Result(QueueableJob job) {
            this.asyncType = Async.AsyncType.QUEUEABLE;
            this.salesforceJobId = job.salesforceJobId;
            this.customJobId = job.customJobId;
            this.job = job;
        }

        public Result setAsyncType(AsyncType asyncType) {
            this.asyncType = asyncType;
            return this;
        }

        public Result setQueueableChainState(QueueableChainState queueableChainState) {
            this.queueableChainState = queueableChainState;
            return this;
        }

        public Result setCurrentQueueableChainState() {
            this.queueableChainState = new QueueableChainState().setCurrentQueueableChainState();
            return this;
        }
    }

    public class QueueableChainState {
        public List<QueueableJob> jobs;
        public Id nextSalesforceJobId;
        public String nextCustomJobId;
        public QueueableManager.EnqueueType enqueueType;

        public QueueableChainState setCurrentQueueableChainState() {
            QueueableChain chain = QueueableManager.get().getChain();
            setJobs(chain.getJobs());
            setNextCustomJobIdFromFirstJob();
            setNextSalesforceJobIdFromFirstJob();
            return this;
        }

        public QueueableChainState setJobs(List<QueueableJob> jobs) {
            this.jobs = jobs;
            return this;
        }

        public QueueableChainState setNextSalesforceJobIdFromFirstJob() {
            if (jobs == null || jobs.isEmpty()) {
                return this;
            }
            return setNextSalesforceJobId(jobs.get(0).salesforceJobId);
        }

        public QueueableChainState setNextSalesforceJobId(Id jobId) {
            this.nextSalesforceJobId = jobId;
            return this;
        }

        public QueueableChainState setNextCustomJobIdFromFirstJob() {
            if (jobs == null || jobs.isEmpty()) {
                return this;
            }
            this.nextCustomJobId = jobs.get(0).customJobId;
            return this;
        }

        public QueueableChainState setEnqueueType(QueueableManager.EnqueueType enqueueType) {
            this.enqueueType = enqueueType;
            return this;
        }
    }

    public enum AsyncType {
        QUEUEABLE,
        BATCHABLE,
        SCHEDULABLE
    }

    public enum Outcome {
        SUCCESS,
        FAILURE,
        COMPLETED
    }

    public class Dependency {
        public Boolean previous = false;
        public String resolvedTargetCustomJobId;
        public Outcome requiredOutcome;

        public Dependency onCustomJobId(String customJobId) {
            this.resolvedTargetCustomJobId = customJobId;
            return this;
        }

        public Dependency onPrevious() {
            this.previous = true;
            return this;
        }

        public Dependency succeeded() {
            this.requiredOutcome = Outcome.SUCCESS;
            return this;
        }

        public Dependency failed() {
            this.requiredOutcome = Outcome.FAILURE;
            return this;
        }

        public Dependency finished() {
            this.requiredOutcome = Outcome.COMPLETED;
            return this;
        }
    }

    public class IllegalArgumentException extends Exception {
    }
}
