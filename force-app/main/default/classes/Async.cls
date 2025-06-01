public inherited sharing class Async {
    public static QueueableManager of(QueueableJob job) {
        return QueueableManager.get()
            .setJob(job);
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
    }

    public class AsyncResult {
        public String jobId;
        public Boolean isEnqueuedViaBatch;
    }

    public class IllegalArgumentException extends Exception {
    }
}
