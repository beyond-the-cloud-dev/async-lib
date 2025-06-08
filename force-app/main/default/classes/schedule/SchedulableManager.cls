public inherited sharing class SchedulableManager {
    private static SchedulableManager instance;

    public Async.AsyncResult schedule(SchedulableBuilder builder) {
        if (builder == null || builder.scheduleJob == null) {
            throw new Async.IllegalArgumentException('Batch job must be set.');
        }
        if (String.isBlank(builder.name)) {
            throw new Async.IllegalArgumentException('Job name must be set.');
        }
        if (String.isBlank(builder.cronExpression) && builder.minutesFromNow == null) {
            throw new Async.IllegalArgumentException('Cron expression or minutes from now must be set.');
        }
        if (builder.cronExpression != null && builder.minutesFromNow != null) {
            throw new Async.IllegalArgumentException('Cannot set both cron expression and minutes from now.');
        }
        if (builder.minutesFromNow != null && builder?.batchableBuilder?.job == null) {
            throw new Async.IllegalArgumentException('Job must be a batch job when using minutes from now.');
        }
        
        Id jobId;
        if (builder.minutesFromNow != null) {
            jobId = System.scheduleBatch(builder.batchableBuilder.job, builder.name, builder.minutesFromNow, builder.batchableBuilder.scopeSize ?? BatchableManager.DEFAULT_BATCH_SIZE);
        } else {
            jobId = System.schedule(builder.name, builder.cronExpression, builder.scheduleJob);
        }

        Async.AsyncResult result = new Async.AsyncResult(jobId);
        return result;
    }

    public static SchedulableManager get() {
        if (instance == null) {
            instance = new SchedulableManager();
        }
        return instance;
    }
}
