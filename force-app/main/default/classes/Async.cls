public inherited sharing class Async {
    public static QueueableManager queueable(Queueable job) {
        return QueueableManager.get()
            .queueable(job);
    }

    public static QueueableManager queueable(QueueableJob job) {
        return QueueableManager.get()
            .queueable(job);
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
