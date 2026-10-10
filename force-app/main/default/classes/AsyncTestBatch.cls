/**
 * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
 *
 * v3.1.0
 *
 * Apex only lets a top-level class implement Database.Batchable, so the failing batch that
 * AsyncTest drives cannot be one of its inner fixtures.
 *
 * PMD False Positives:
 * - EmptyStatementBlock: Database.Batchable requires finish(), and this fixture has nothing to do
 **/
@SuppressWarnings('PMD.EmptyStatementBlock')
@IsTest
public class AsyncTestBatch implements Database.Batchable<SObject>, Database.RaisesPlatformEvents {
    public static final String FAILURE_MESSAGE = 'The batch scope failed.';
    public static final String ACCOUNT_NAME_PREFIX = 'BATCH-';

    public static Boolean startFails = false;
    public static Boolean executeFails = false;
    public static Boolean readsOwner = false;
    public static Boolean readsOnlyId = false;

    public Database.QueryLocator start(Database.BatchableContext bc) {
        if (startFails) {
            throw new BatchFailedException(FAILURE_MESSAGE);
        }
        return Database.getQueryLocator(
            [SELECT Id, Name FROM Account WHERE Name LIKE :ACCOUNT_NAME_PREFIX + '%']
        );
    }

    public void execute(Database.BatchableContext bc, List<Account> scope) {
        if (executeFails) {
            throw new BatchFailedException(FAILURE_MESSAGE);
        }
        List<Account> processed = new List<Account>();
        for (Account account : scope) {
            processed.add(new Account(Id = account.Id, Site = outcomeFor(account)));
        }
        update processed;
    }

    public void finish(Database.BatchableContext bc) {
    }

    private String outcomeFor(Account account) {
        if (readsOnlyId) {
            return 'id-only';
        }
        return readsOwner ? 'owner:' + account.Owner.Name : 'processed:' + account.Name;
    }

    public class BatchFailedException extends Exception {
    }
}
