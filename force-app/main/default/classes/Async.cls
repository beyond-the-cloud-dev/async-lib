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
        public QueueableJob currentJob;
        
        public AsyncContext(QueueableContext qc, QueueableJob currentJob) {
            this.qc = qc;
            this.currentJob = currentJob;
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
