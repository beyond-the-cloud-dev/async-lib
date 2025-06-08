public inherited sharing class SchedulableBuilder {
    public Schedulable scheduleJob;
    public String name;
    public String cronExpression;
    public Integer minutesFromNow;
    public BatchableBuilder batchableBuilder;

    public SchedulableBuilder(BatchableBuilder builder) {
        this.batchableBuilder = builder;
        this.scheduleJob = new SchedulableBatch(builder);
    }

    public SchedulableBuilder(Schedulable scheduleJob) {
        this.scheduleJob = scheduleJob;
    }

    public SchedulableBuilder name(String name) {
        this.name = name;
        return this;
    }

    public SchedulableBuilder cronExpression(String cronExpression) {
        this.cronExpression = cronExpression;
        return this;
    }

    public SchedulableBuilder cronExpression(CronBuilder cronBuilder) {
        this.cronExpression = cronBuilder.getCronExpression();
        return this;
    }

    public SchedulableBuilder minutesFromNow(Integer minutes) {
        if (minutes < 0) {
            throw new Async.IllegalArgumentException('Minutes from now must be zero or greater.');
        }
        this.minutesFromNow = minutes;
        return this;
    }

    public Async.AsyncResult schedule() {
        return SchedulableManager.get().schedule(this);
    }
}
