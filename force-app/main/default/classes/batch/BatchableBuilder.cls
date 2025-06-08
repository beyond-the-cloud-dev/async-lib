public inherited sharing class BatchableBuilder {
    public Database.Batchable<Object> job;
    public Integer scopeSize;

    public BatchableBuilder(Database.Batchable<Object> job) {
        this.job = job;
    }

    public BatchableBuilder scopeSize(Integer scopeSize) {
        if (scopeSize <= 0) {
            throw new Async.IllegalArgumentException('Scope size must be greater than zero.');
        }
        this.scopeSize = scopeSize;
        return this;
    }

    public SchedulableBuilder asSchedule() {
        return new SchedulableBuilder(this);
    }

    public Async.AsyncResult execute() {
        return BatchableManager.get().execute(this);
    }
}
