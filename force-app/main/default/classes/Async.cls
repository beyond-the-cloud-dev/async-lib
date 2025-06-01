public inherited sharing class Async {
    public static QueueableManager of(QueueableJob job) {
        return QueueableManager.get()
            .setJob(job);
    }

    public static QueueableJobContext getQueueableJobContext() {
        return QueueableManager.get()
            .getQueueableJobContext();
    }

    public class QueueableJobContext {
        public QueueableJob currentJob;
    }

    public class AsyncResult {
        public String jobId;
        public String jobName;
        public String status;
        public String errorMessage;
    }

    public class IllegalArgumentException extends Exception {
    }
}
