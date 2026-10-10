/**
 * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
 *
 * v3.1.0
 **/
public class NsFailingBatch implements Database.Batchable<SObject>, Database.RaisesPlatformEvents {
    public static Boolean fails = false;
    public static Boolean readsOwner = false;

    public class NsBatchException extends Exception {
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(
            [SELECT Id, Name FROM Account WHERE Name LIKE 'NS-BATCH-%']
        );
    }

    public void execute(Database.BatchableContext bc, List<Account> scope) {
        if (fails) {
            throw new NsBatchException('ns batch failure');
        }
        List<Account> processed = new List<Account>();
        for (Account account : scope) {
            processed.add(
                new Account(
                    Id = account.Id,
                    Site = 'ns-processed:' + account.Name,
                    Description = readsOwner ? account.Owner.Name : null
                )
            );
        }
        update processed;
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('NsFailingBatch finished');
    }
}
