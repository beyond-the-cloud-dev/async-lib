/**
 * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
 *
 * v3.0.0
 *
 * PMD False Positives:
 * - AvoidDebugStatements: the trigger must never throw, so the debug log is the only channel left
 *   when recording itself fails
 **/
@SuppressWarnings('PMD.AvoidDebugStatements')
public inherited sharing class BatchFailureRecorder {
    public static final String PHASE_EXECUTE = 'EXECUTE';

    private static final Integer MAX_EXCEPTION_MESSAGE_LENGTH = 32768;
    private static final String RESULT_UNHANDLED_EXCEPTION = 'UNHANDLED_EXCEPTION';
    private static final String COULD_NOT_RECORD = 'Async Lib could not record a batch failure: ';

    public static void record(List<BatchApexErrorEvent> events) {
        try {
            recordAndNotify(events);
        } catch (Exception recordingFailure) {
            reportWithoutLosingTheOtherFailuresInThisDelivery(recordingFailure);
        }
    }

    private static void reportWithoutLosingTheOtherFailuresInThisDelivery(
        Exception recordingFailure
    ) {
        System.debug(
            LoggingLevel.ERROR,
            COULD_NOT_RECORD +
                recordingFailure.getTypeName() +
                ': ' +
                recordingFailure.getMessage() +
                '\n' +
                recordingFailure.getStackTraceString()
        );
    }

    private static void recordAndNotify(List<BatchApexErrorEvent> events) {
        Map<Id, AsyncApexJob> jobById = jobsReportedBy(events);
        List<AsyncResult__c> failures = new List<AsyncResult__c>();
        List<AsyncResult__c> toInsert = new List<AsyncResult__c>();
        for (BatchApexErrorEvent event : events) {
            AsyncResult__c failure = failureFrom(event, jobById.get(event.AsyncApexJobId));
            failures.add(failure);
            if (createResultEnabledFor(failure.ClassName__c)) {
                toInsert.add(failure);
            }
        }
        insert as system toInsert;
        for (AsyncResult__c failure : failures) {
            AsyncEventDispatcher.batchFailed(
                new Async.FailureContext(failure),
                QueueableManager.settingFor(
                    failure.ClassName__c,
                    QueueableJobSetting__mdt.LoggerClass__c
                )
            );
        }
    }

    private static Map<Id, AsyncApexJob> jobsReportedBy(List<BatchApexErrorEvent> events) {
        Set<Id> jobIds = new Set<Id>();
        for (BatchApexErrorEvent event : events) {
            jobIds.add(event.AsyncApexJobId);
        }
        return new Map<Id, AsyncApexJob>(
            [
                SELECT Id, ParentJobId, ApexClass.Name, ApexClass.NamespacePrefix
                FROM AsyncApexJob
                WHERE Id IN :jobIds
                WITH SYSTEM_MODE
            ]
        );
    }

    private static AsyncResult__c failureFrom(BatchApexErrorEvent event, AsyncApexJob reportedJob) {
        return new AsyncResult__c(
            SalesforceJobId__c = batchJobIdFor(event, reportedJob),
            ClassName__c = classNameOf(reportedJob),
            Status__c = QueueableManager.STATUS_FAILED,
            Result__c = RESULT_UNHANDLED_EXCEPTION,
            ExceptionType__c = event.ExceptionType,
            ExceptionMessage__c = event.Message?.left(MAX_EXCEPTION_MESSAGE_LENGTH),
            BatchPhase__c = event.Phase,
            BatchScope__c = event.JobScope,
            BatchScopeTruncated__c = event.DoesExceedJobScopeMaxLength == true
        );
    }

    // An EXECUTE failure reports the BatchApexWorker child job, not the id Database.executeBatch
    // returned. START and FINISH failures report the batch job itself.
    private static Id batchJobIdFor(BatchApexErrorEvent event, AsyncApexJob reportedJob) {
        return reportedJob?.ParentJobId ?? (Id) event.AsyncApexJobId;
    }

    @TestVisible
    private static String classNameOf(AsyncApexJob job) {
        if (job?.ApexClass == null) {
            return null;
        }
        return String.isBlank(job.ApexClass.NamespacePrefix)
            ? job.ApexClass.Name
            : job.ApexClass.NamespacePrefix + '.' + job.ApexClass.Name;
    }

    private static Boolean createResultEnabledFor(String className) {
        Map<String, QueueableJobSetting__mdt> settings = QueueableChain.jobSettingByName;
        return settings.get(QueueableManager.QUEUEABLE_JOB_SETTING_ALL)?.CreateResult__c == true ||
            settings.get(className)?.CreateResult__c == true;
    }
}
