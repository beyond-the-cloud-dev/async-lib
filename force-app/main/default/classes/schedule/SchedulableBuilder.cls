public inherited sharing class SchedulableBuilder {
    public Schedulable scheduleJob;
    public BatchableBuilder batchableBuilder;

    public String name;
    public List<CronBuilder> crons = new List<CronBuilder>();
    public Boolean skipWhenAlreadyScheduled = false;

    public SchedulableBuilder(QueueableBuilder builder) {
        this.scheduleJob = new QueueableSchedulable(builder);
    }

    public SchedulableBuilder(BatchableBuilder builder) {
        this.batchableBuilder = builder;
        this.scheduleJob = new BatchableSchedulable(builder);
    }

    public SchedulableBuilder(Schedulable scheduleJob) {
        this.scheduleJob = scheduleJob;
    }

    public SchedulableBuilder name(String name) {
        this.name = name;
        return this;
    }

    public SchedulableBuilder cronExpression(String cronExpression) {
        return cronExpression(new CronBuilder(cronExpression));
    }

    public SchedulableBuilder cronExpression(CronBuilder builder) {
        return cronExpression(new List<CronBuilder> {builder});
    }

    public SchedulableBuilder cronExpression(List<CronBuilder> builders) {
        this.crons.addAll(builders);
        return this;
    }

    public SchedulableBuilder skipWhenAlreadyScheduled() {
        this.skipWhenAlreadyScheduled = true;
        return this;
    }

    public List<Async.Result> schedule() {
        return SchedulableManager.get().schedule(this);
    }
}
