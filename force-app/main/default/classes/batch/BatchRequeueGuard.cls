/**
 * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
 *
 * v3.1.0
 **/
public inherited sharing class BatchRequeueGuard {
    // In a test a failed batch job stays Processing with NumberOfErrors 0.
    @TestVisible
    private static Integer failedScopesReportedInTest;

    public static Database.Batchable<SObject> asBatch(Object candidate) {
        if (candidate == null) {
            throw new Async.IllegalArgumentException(QueueableManager.ERROR_MESSAGE_NOT_A_BATCH);
        }
        try {
            return (Database.Batchable<SObject>) candidate;
        } catch (TypeException notABatch) {
            throw new Async.IllegalArgumentException(QueueableManager.ERROR_MESSAGE_NOT_A_BATCH);
        }
    }

    public static void assertJobIdAndLoaderGiven(Id batchJobId, Async.BatchRecordLoader loader) {
        if (batchJobId == null) {
            throw new Async.IllegalArgumentException(
                QueueableManager.ERROR_MESSAGE_BATCH_JOB_ID_REQUIRED
            );
        }
        if (loader == null) {
            throw new Async.IllegalArgumentException(
                String.format(
                    QueueableManager.ERROR_MESSAGE_BATCH_RELOAD_REQUIRED,
                    new List<String>{ QueueableManager.API_PREFIX }
                )
            );
        }
    }

    public static void assertLoaderOutlivesThisTransaction(Async.BatchRecordLoader loader) {
        assertIsSavedClass(runtimeClassNameOf(loader));
    }

    public static void assertTheJobReallyHadNoFailures(Id batchJobId) {
        List<AsyncApexJob> batchJobs = [
            SELECT NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :batchJobId AND JobType = 'BatchApex'
            WITH SYSTEM_MODE
        ];
        if (batchJobs.isEmpty()) {
            throw new Async.IllegalArgumentException(
                String.format(
                    QueueableManager.ERROR_MESSAGE_BATCH_JOB_NOT_FOUND,
                    new List<String>{ batchJobId }
                )
            );
        }
        Integer failedScopes = failedScopesReportedInTest ?? batchJobs[0].NumberOfErrors;
        if (failedScopes > 0) {
            throw new Async.IllegalArgumentException(
                String.format(
                    QueueableManager.ERROR_MESSAGE_BATCH_FAILURES_NOT_VISIBLE,
                    new List<String>{ batchJobId, String.valueOf(failedScopes) }
                )
            );
        }
    }

    public static void assertSameClass(Database.Batchable<SObject> batch, AsyncResult__c failure) {
        String passedIn = runtimeClassNameOf(batch);
        String recorded = failure.ClassName__c;
        if (passedIn == recorded) {
            return;
        }
        throw new Async.IllegalArgumentException(
            String.format(
                QueueableManager.ERROR_MESSAGE_BATCH_CLASS_MISMATCH,
                new List<String>{ failure.Id, recorded, passedIn }
            )
        );
    }

    @TestVisible
    private static void assertIsSavedClass(String className) {
        Integer savedClasses = [
            SELECT COUNT()
            FROM ApexClass
            WHERE Name IN :className.split('\\.')
            WITH SYSTEM_MODE
        ];
        if (savedClasses == 0) {
            throw new Async.IllegalArgumentException(
                String.format(
                    QueueableManager.ERROR_MESSAGE_LOADER_NOT_A_SAVED_CLASS,
                    new List<String>{ className }
                )
            );
        }
    }

    private static String runtimeClassNameOf(Object instance) {
        String runtimeClassName;
        try {
            // A failed cast is the only way to read the runtime type with its namespace.
            String.valueOf((Datetime) instance);
        } catch (TypeException expectedTypeException) {
            runtimeClassName = expectedTypeException.getMessage()
                .substringAfter('Invalid conversion from runtime type ')
                .substringBefore(' to Datetime');
        }
        return runtimeClassName;
    }
}
