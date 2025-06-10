public inherited sharing class SchedulableManager {
    @TestVisible
    private static final String ERROR_MESSAGE_JOB_NOT_SET = 'Batch job must be set.';
    @TestVisible
    private static final String ERROR_MESSAGE_JOB_NAME = 'Job name must be set.';
    @TestVisible
    private static final String ERROR_MESSAGE_CRON_AND_MINUTES_NOT_SET = 'Cron expressions or minutes from now must be set.';
    @TestVisible
    private static final String ERROR_MESSAGE_CRON_AND_MINUTES_SET = 'Cannot set both cron expressions and minutes from now.';
    @TestVisible
    private static final String ERROR_MESSAGE_JOB_BATCHABLE = 'Job must be a batch job when using minutes from now.';

    private static SchedulableManager instance;

    public List<Async.AsyncResult> schedule(SchedulableBuilder builder) {
        if (builder == null || builder.scheduleJob == null) {
            throw new Async.IllegalArgumentException(ERROR_MESSAGE_JOB_NOT_SET);
        }
        if (String.isBlank(builder.name)) {
            throw new Async.IllegalArgumentException(ERROR_MESSAGE_JOB_NAME);
        }
        if ((builder.crons == null || builder.crons.isEmpty()) && builder.batchableBuilder?.minutesFromNow == null) {
            throw new Async.IllegalArgumentException(ERROR_MESSAGE_CRON_AND_MINUTES_NOT_SET);
        }
        if ((builder.crons != null && !builder.crons.isEmpty()) && builder.batchableBuilder?.minutesFromNow != null) {
            throw new Async.IllegalArgumentException(ERROR_MESSAGE_CRON_AND_MINUTES_SET);
        }
        
        List<Async.AsyncResult> results = new List<Async.AsyncResult>();
        if (builder.batchableBuilder?.minutesFromNow != null) {
            results.add(
                new Async.AsyncResult(
                    System.scheduleBatch(
                        builder.batchableBuilder.job, 
                        builder.name, 
                        builder.batchableBuilder.minutesFromNow, 
                        builder.batchableBuilder.scopeSize ?? BatchableManager.DEFAULT_BATCH_SIZE
                    )
                )
            );
        } else {
            for (CronBuilder cron : builder.crons) {
                results.add(
                    new Async.AsyncResult(
                        System.schedule(
                            builder.name + (builder.crons.size() == 1 ? '' : '/' + cron.minute),
                            cron.getCronExpression(),
                            builder.scheduleJob
                        )
                    )
                );
            }
        }

        return results;
    }

    public static SchedulableManager get() {
        if (instance == null) {
            instance = new SchedulableManager();
        }
        return instance;
    }
}
