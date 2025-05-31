public inherited sharing class Async {
    public static QueueableManager of(Queueable job) {
        return QueueableManager.get()
            .setJob(job);
    }

    public static QueueableManager of(QueueableJob job) {
        return QueueableManager.get()
            .setJob(job);
    }

    public class AsyncContext {
        public QueueableContext qc;

        public AsyncContext(QueueableContext qc) {
            this.qc = qc;
        }
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
