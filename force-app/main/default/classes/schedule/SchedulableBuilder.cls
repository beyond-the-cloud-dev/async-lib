public inherited sharing class SchedulableBuilder {
    public Schedulable scheduleJob;
    public String name;
    public List<CronBuilder> crons = new List<CronBuilder>();
    public Async.AsyncBatchableBuilder batchableBuilder;

    public SchedulableBuilder(QueueableBuilder builder) {
        this.scheduleJob = new QueueableSchedulable(builder);
    }

    public SchedulableBuilder(Async.AsyncBatchableBuilder builder) {
        this.batchableBuilder = builder;
        this.scheduleJob = new Async.BatchableSchedulable(builder);
    }

    public SchedulableBuilder(Schedulable scheduleJob) {
        this.scheduleJob = scheduleJob;
    }

    public SchedulableBuilder name(String name) {
        this.name = name;
        return this;
    }

    public SchedulableBuilder cronExpression(String cronExpression) {
        this.crons.add(new CronBuilder(cronExpression));
        return this;
    }

    public SchedulableBuilder cronExpression(CronBuilder builder) {
        this.crons.add(builder);
        return this;
    }

    public SchedulableBuilder cronExpression(List<CronBuilder> builders) {
        this.crons.addAll(builders);
        return this;
    }

    public List<Async.AsyncResult> schedule() {
        return SchedulableManager.get().schedule(this);
    }
}
