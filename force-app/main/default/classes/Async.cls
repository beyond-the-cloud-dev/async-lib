public inherited sharing class Async {
    public static QueueableBuilder queueable(QueueableJob job) {
        return new QueueableBuilder(job);
    }

    public static BatchableBuilder batchable(Object job) {
        return new BatchableBuilder(job); 
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
        public List<Id> salesforceJobIds;
        public String customJobId;
        public Boolean isChained;

        public AsyncResult(Id salesforceJobId) {
            this.salesforceJobId = salesforceJobId;
        }

        public AsyncResult(List<Id> salesforceJobIds) {
            if (salesforceJobIds.size() == 1) {
                this.salesforceJobId = salesforceJobIds[0];
            } else {
                this.salesforceJobIds = salesforceJobIds;
            }
        }

        public AsyncResult(QueueableJob job) {
            this.salesforceJobId = job.salesforceJobId;
            this.customJobId = job.customJobId;
            this.isChained = String.isBlank(salesforceJobId);
        }
    }

    public class IllegalArgumentException extends Exception {
    }
}
