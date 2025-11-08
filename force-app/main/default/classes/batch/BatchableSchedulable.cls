public class BatchableSchedulable implements Schedulable {
    public BatchableBuilder builder;

    public BatchableSchedulable(BatchableBuilder builder) {
        this.builder = builder;
    }

    public void execute(SchedulableContext scx) {
        builder.execute();
    }
}
