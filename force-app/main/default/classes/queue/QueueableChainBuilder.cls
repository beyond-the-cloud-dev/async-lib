public inherited sharing class QueueableChainBuilder {
    private List<QueueableJob> jobs = new List<QueueableJob>();

    public QueueableChainBuilder add(QueueableJob job) {
        return add(new List<QueueableJob>{ job });
    }

    public QueueableChainBuilder add(List<QueueableJob> jobs) {
        this.jobs.addAll(jobs);
        return this;
    }

    public Async.Result enqueue() {
        return new QueueableBuilder(jobs).enqueue();
    }

    public Async.Result chain() {
        return new QueueableBuilder(jobs).chain();
    }
}
