public inherited sharing class QueueableService {
    private static QueueableChain chain = new QueueableChain();
    private static QueueableResult result;

    public static void enqueueJob(QueueableChainItem item, Integer delay) {
        item.delay = delay;
        enqueueJob(item);
    }

    public static void enqueueJob(QueueableChainItem item, AsyncOptions asyncOptions) {
        item.asyncOptions = asyncOptions;
        enqueueJob(item);
    }

    public static void enqueueJob(QueueableChainItem item) {
        item.className = getClassName(item);
        item.name = getItemName(item);
        chain.addItem(item);

        if (System.isQueueable()) {
            return;
        }

        if (areQueueableLimitsExceeded()) {
            chain.scheduleOrReplaceInitialChainJob();
            setQueueableResultScheduledJobName(QueueableChainScheduler.UNIQUEUE_QUEUEABLE_CHAIN_SCHEDULER_NAME);
        } else {
            enqueueJobSeparatelyAndResetChain();
        }
    }

    public static QueueableResult getResult() {
        return result;
    }

    // Allow to pass chain that is currently used in Queueable context,
    // so all other logic will start adding jobs to the existing on
    public static void setChainInQueueableContext(QueueableChain chain) {
        QueueableService.chain = chain;
    }

    private static String getClassName(QueueableChainItem item) {
        return String.valueOf(item).substringBefore(':');
    }

    private static String getItemName(QueueableChainItem item) {
        return item.className + '::' + System.now().format();
    }

    private static Boolean areQueueableLimitsExceeded() {
        // we can add to maximum, since initial Chain Job is scheduled not enqueued
        return Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs();
    }

    private static void enqueueJobSeparatelyAndResetChain() {
        Id queueableJobId = chain.enqueueNextItemIfAny();
        setQueueableResultJobId(queueableJobId);
        chain = new QueueableChain();
    }

    private static void setQueueableResultJobId(Id jobId) {
        result = new QueueableResult();
        result.jobId = jobId;
    }

    private static void setQueueableResultScheduledJobName(String scheduledJobName) {
        result = new QueueableResult();
        result.scheduledJobName = scheduledJobName;
    }

    public class QueueableResult {
        public Id jobId;
        // if limit was reached, we can check if the all the jobs finished by
        // checking if the scheduled job was deleted (what happens after all of them will finish)
        public String scheduledJobName;
    }
}
