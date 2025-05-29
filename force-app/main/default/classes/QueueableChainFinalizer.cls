public without sharing class QueueableChainFinalizer implements Finalizer {
    private String scheduleJobName;

    public QueueableChainFinalizer(String scheduledQueueableChainName) {
        scheduleJobName = scheduledQueueableChainName;
    }

    public void execute(FinalizerContext context) {
        QueueableChainScheduler.removeScheduledJobByNameIfExists(scheduleJobName);
    }
}
