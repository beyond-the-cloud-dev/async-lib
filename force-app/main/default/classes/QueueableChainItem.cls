public abstract class QueueableChainItem {
    public String className;
    public String name;
    public Integer delay;
    public AsyncOptions asyncOptions;

    public abstract void work(QueueableContext ctx);
}
