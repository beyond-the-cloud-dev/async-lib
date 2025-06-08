public class SchedulableBatch implements Schedulable {
    public BatchableBuilder builder;
    
    public SchedulableBatch(BatchableBuilder builder) {
        this.builder = builder;
    }

    public void execute(SchedulableContext scx) {
        builder.execute();
    }
}