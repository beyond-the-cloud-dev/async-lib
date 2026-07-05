public inherited sharing class AsyncResultCleanupBatch implements Database.Batchable<SObject> {
    public static final String ERROR_MESSAGE_NO_RETENTION_CONFIGURED = 'Configure at least one retention track: failedOlderThanDays(...) and/or othersOlderThanDays(...).';
    public static final String ERROR_MESSAGE_INVALID_RETENTION_DAYS = 'Retention days must be greater than zero.';

    public Integer failedRetentionDays;
    public Integer othersRetentionDays;

    public AsyncResultCleanupBatch failedOlderThanDays(Integer days) {
        validateDays(days);
        this.failedRetentionDays = days;
        return this;
    }

    public AsyncResultCleanupBatch othersOlderThanDays(Integer days) {
        validateDays(days);
        this.othersRetentionDays = days;
        return this;
    }

    public Database.QueryLocator start(Database.BatchableContext ctx) {
        if (failedRetentionDays == null && othersRetentionDays == null) {
            throw new IllegalArgumentException(ERROR_MESSAGE_NO_RETENTION_CONFIGURED);
        }
        Datetime failedCutoff = cutoff(failedRetentionDays);
        Datetime othersCutoff = cutoff(othersRetentionDays);
        if (othersCutoff == null) {
            return Database.getQueryLocator(
                [
                    SELECT Id
                    FROM AsyncResult__c
                    WHERE
                        Status__c = :QueueableManager.STATUS_FAILED
                        AND CreatedDate < :failedCutoff
                ]
            );
        }
        if (failedCutoff == null) {
            return Database.getQueryLocator(
                [
                    SELECT Id
                    FROM AsyncResult__c
                    WHERE
                        Status__c != :QueueableManager.STATUS_FAILED
                        AND CreatedDate < :othersCutoff
                ]
            );
        }
        return Database.getQueryLocator(
            [
                SELECT Id
                FROM AsyncResult__c
                WHERE
                    (Status__c = :QueueableManager.STATUS_FAILED
                    AND CreatedDate < :failedCutoff)
                    OR (Status__c != :QueueableManager.STATUS_FAILED
                    AND CreatedDate < :othersCutoff)
            ]
        );
    }

    public void execute(Database.BatchableContext ctx, List<AsyncResult__c> scope) {
        delete as system scope;
    }

    public void finish(Database.BatchableContext ctx) {
    }

    private void validateDays(Integer days) {
        if (days == null || days <= 0) {
            throw new IllegalArgumentException(ERROR_MESSAGE_INVALID_RETENTION_DAYS);
        }
    }

    private Datetime cutoff(Integer retentionDays) {
        return retentionDays == null ? null : System.now().addDays(-retentionDays);
    }
}
