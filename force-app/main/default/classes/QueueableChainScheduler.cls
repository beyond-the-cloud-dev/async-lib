public with sharing class QueueableChainScheduler implements Schedulable {
    // this class allows to overcome Apex limitation, where if we abort the queueable job in the same transaction it was enqueued, it will still count to the limits
    // since we don't know when the last queueable job will be enqueued, and we need to enqueu it with all the chain items, this is a workaround
    public static final String QUEUEABLE_CHAIN_SCHEDULER_NAME = 'Queueable Chain Scheduler';

    public static final String UNIQUEUE_QUEUEABLE_CHAIN_SCHEDULER_NAME {
        get {
            if (UNIQUEUE_QUEUEABLE_CHAIN_SCHEDULER_NAME == null) {
                UNIQUEUE_QUEUEABLE_CHAIN_SCHEDULER_NAME = getScheduleJobName();
            }
            return UNIQUEUE_QUEUEABLE_CHAIN_SCHEDULER_NAME;
        }
        private set;
    }

    private QueueableChain chain;

    public QueueableChainScheduler(QueueableChain chain) {
        this.chain = chain;
    }

    public void execute(SchedulableContext sc) {
        chain.enqueueNextItemIfAny();
    }

    public static Id scheduleChainJob(QueueableChain chain) {
        return System.schedule(
            UNIQUEUE_QUEUEABLE_CHAIN_SCHEDULER_NAME,
            getCronString(Datetime.now().addMinutes(1)),
            new QueueableChainScheduler(chain)
        );
    }

    public static void removeScheduledJobByNameIfExists(String scheduleJobName) {
        List<CronTrigger> jobs = [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name = :scheduleJobName
        ];
        if (!jobs.isEmpty()) {
            System.abortJob(jobs.get(0).Id);
        }
    }

    public static void removeScheduledJobByIdIfExists(Id jobId) {
        if (jobId == null) {
            return;
        }

        try {
            System.abortJob(jobId);
        } catch (Exception e) {
            // No action if not exists
        }
    }

    public static String getScheduleJobName() {
        String jobName = QUEUEABLE_CHAIN_SCHEDULER_NAME + '::' + String.valueOf(System.currentTimeMillis()) + '::' + String.valueOf(Math.random());
        return jobName.trim();
    }

    private static String getCronString(Datetime dt) {
        return String.valueOf(dt.second()) +
            ' ' +
            String.valueOf(dt.minute()) +
            ' ' +
            String.valueOf(dt.hour()) +
            ' ' +
            String.valueOf(dt.day()) +
            ' ' +
            String.valueOf(dt.month()) +
            ' ' +
            '? ' +
            String.valueOf(dt.year());
    }
}
