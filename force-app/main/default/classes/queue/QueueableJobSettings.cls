/**
 * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
 *
 * v3.2.0
 **/
public inherited sharing class QueueableJobSettings {
    @TestVisible
    public static Map<String, QueueableJobSetting__mdt> jobSettingByName {
        get {
            if (jobSettingByName == null) {
                jobSettingByName = fromCustomMetadata();
            }
            return jobSettingByName;
        }
        private set;
    }

    private static Map<String, QueueableJobSetting__mdt> fromCustomMetadata() {
        Map<String, QueueableJobSetting__mdt> settings = new Map<String, QueueableJobSetting__mdt>();
        for (QueueableJobSetting__mdt setting : QueueableJobSetting__mdt.getAll().values()) {
            settings.put(setting.QueueableJobName__c, setting);
        }
        return settings;
    }

    public static QueueableJobSetting__mdt forAllJobs() {
        return jobSettingByName.get(QueueableManager.QUEUEABLE_JOB_SETTING_ALL);
    }

    public static Boolean createResultEnabledFor(QueueableJob job) {
        return forAllJobs()?.CreateResult__c == true ||
            jobSettingByName.get(job.className)?.CreateResult__c == true;
    }

    public static Boolean isDisabled(QueueableJob job) {
        return jobSettingByName.get(job.className)?.IsDisabled__c == true;
    }

    public static void applyRetryDefaults(QueueableJob job) {
        if (job.maxRetries > 0) {
            return;
        }

        QueueableJobSetting__mdt setting = retrySettingFor(job.className);
        if (setting == null) {
            return;
        }

        if (!QueueableManager.declaresRetryStateHandling(job)) {
            job.recordConfigurationWarning(
                String.format(
                    QueueableManager.WARNING_CMDT_RETRY_WITHOUT_RESET,
                    new List<String>{ job.className, QueueableManager.API_PREFIX }
                )
            );
            return;
        }

        job.maxRetries = QueueableManager.cappedRetries(job, setting.MaxRetries__c.intValue());
        QueueableManager.applyBackoffDefault(job, setting);

        if (job.retryOnExceptionTypes == null) {
            job.retryOnExceptionTypes = parseExceptionTypes(setting.RetryableExceptions__c);
        }
    }

    private static QueueableJobSetting__mdt retrySettingFor(String jobClassName) {
        QueueableJobSetting__mdt setting = jobSettingByName.get(jobClassName);
        if (setting == null || setting.MaxRetries__c == null) {
            setting = forAllJobs();
        }
        Boolean hasRetryDefault =
            setting != null &&
            setting.MaxRetries__c != null &&
            setting.MaxRetries__c > 0;
        return hasRetryDefault ? setting : null;
    }

    private static Set<String> parseExceptionTypes(String csv) {
        if (String.isBlank(csv)) {
            return null;
        }
        Set<String> types = new Set<String>();
        for (String exceptionType : csv.split(',')) {
            if (String.isNotBlank(exceptionType)) {
                types.add(exceptionType.trim());
            }
        }
        return types.isEmpty() ? null : types;
    }
}
