public inherited sharing class QueueableSchedulable implements Schedulable {
    public QueueableBuilder builder;
    
    public QueueableSchedulable(QueueableBuilder builder) {
        this.builder = builder;
    }

    public void execute(SchedulableContext scx) {
        builder.enqueue();
    }
}