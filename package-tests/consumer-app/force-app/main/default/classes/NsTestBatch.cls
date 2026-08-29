public class NsTestBatch implements Database.Batchable<SObject> {
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator('SELECT Id FROM Account LIMIT 1');
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        System.debug('NsTestBatch execute with ' + scope.size() + ' records');
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('NsTestBatch finished!');
    }
}
