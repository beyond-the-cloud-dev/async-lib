public with sharing class QueueableChain implements Queueable, Database.AllowsCallouts {
    private List<QueueableChainItem> items = new List<QueueableChainItem>();
    private Id scheduledJobId;
    private String scheduledJobName;
    private Integer counter = 0;

    public void execute(QueueableContext ctx) {
        QueueableService.setChainInQueueableContext(this);
        executeCurrentItem(ctx);
        enqueueNextItemIfAny();
        setFinalizerIfFinished();
    }

    public void executeCurrentItem(QueueableContext ctx) {
        if (items.isEmpty()) {
            return;
        }

        QueueableChainItem currentItem = items.remove(0);
        Savepoint sp = Database.setSavepoint();
        try {
            System.debug(currentItem.name);
            currentItem.work(ctx);
        } catch (Exception ex) {
            Database.rollback(sp);
            Database.releaseSavepoint(sp);
            // Add logger of your choice here
        }
    }

    public Id enqueueNextItemIfAny() {
        if (!hasNextItem() || (Test.isRunningTest() && System.isQueueable())) {
            return null;
        }

        QueueableChainItem nextItem = items.get(0);
        try {
            if (nextItem.delay != null) {
                return System.enqueueJob(this, nextItem.delay);
            } else if (nextItem.asyncOptions != null) {
                return System.enqueueJob(this, nextItem.asyncOptions);
            } else {
                return System.enqueueJob(this);
            }
        } catch (Exception ex) {
            // Add logger of your choice here
            items.remove(0);
            return enqueueNextItemIfAny();
        }
    }

    public void setFinalizerIfFinished() {
        if (hasNextItem()) {
            return;
        }

        System.attachFinalizer(new QueueableChainFinalizer(scheduledJobName));
    }

    public Boolean hasNextItem() {
        return !items.isEmpty();
    }

    public void addItem(QueueableChainItem item) {
        item.name = getNameWithCounterNumber(item);
        items.add(item);
    }

    public void scheduleOrReplaceInitialChainJob() {
        QueueableChainScheduler.removeScheduledJobByIdIfExists(scheduledJobId);
        scheduledJobId = QueueableChainScheduler.scheduleChainJob(this);
        scheduledJobName = QueueableChainScheduler.UNIQUEUE_QUEUEABLE_CHAIN_SCHEDULER_NAME;
    }

    private String getNameWithCounterNumber(QueueableChainItem item) {
        return item.name + '::' + ++counter;
    }
}
