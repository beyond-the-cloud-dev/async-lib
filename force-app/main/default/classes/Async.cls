/**
 * Copyright (c) 2025 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
**/
public inherited sharing class Async implements Database.Batchable<sObject> {
    public interface IQueueableBuilder {
        IQueueableBuilder asyncOptions(AsyncOptions asyncOptions);
        IQueueableBuilder delay(Integer delay);
        IQueueableBuilder priority(Integer priority);
        IQueueableBuilder continueOnJobEnqueueFail();
        IQueueableBuilder continueOnJobExecuteFail();
        IQueueableBuilder rollbackOnJobExecuteFail();
        ISchedulableBuilder asSchedulable();
        AsyncResult attachFinalizer();
        AsyncResult enqueue();
    }

    public interface IBatchableBuilder {
        IBatchableBuilder scopeSize(Integer scopeSize);
        IBatchableBuilder minutesFromNow(Integer minutes);
        ISchedulableBuilder asSchedulable();
        AsyncResult execute();
    }

    public interface ISchedulableBuilder {
        ISchedulableBuilder name(String name);
        ISchedulableBuilder cronExpression(String cronExpression);
        ISchedulableBuilder cronExpression(ICronBuilder builder);
        ISchedulableBuilder cronExpression(List<ICronBuilder> builders);
        List<AsyncResult> schedule();
    }

    public interface ICronBuilder {
        ICronBuilder second(String second);
        ICronBuilder minute(String minute);
        ICronBuilder hour(String hour);
        ICronBuilder dayOfMonth(String dayOfMonth);
        ICronBuilder month(String month);
        ICronBuilder dayOfWeek(String dayOfWeek);
        ICronBuilder optionalYear(String optionalYear);
        List<ICronBuilder> buildForEveryXMinutes(Integer everyXMinutes);
        ICronBuilder everyHour(Integer minute);
        ICronBuilder everyXHours(Integer everyXHours, Integer minute);
        ICronBuilder everyDay(Integer hour, Integer minute);
        ICronBuilder everyXDays(Integer everyXDays, Integer hour, Integer minute);
        ICronBuilder everyMonth(Integer day, Integer hour, Integer minute);
        ICronBuilder everyXMonths(Integer everyXMonths, Integer dayOfMonth, Integer hour, Integer minute);
        String getCronExpression();
    }

    public static IQueueableBuilder queueable(QueueableJob job) {
        return new QueueableBuilder(job);
    }

    public static IBatchableBuilder batchable(Object job) {
        return new BatchableBuilder(job); 
    }

    public static ISchedulableBuilder schedulable(Schedulable scheduleJob) {
        return new SchedulableBuilder(scheduleJob);
    }

    public static QueueableJobContext getQueueableJobContext() {
        return QUEUEABLE_MANAGER_INSTANCE
            .getQueueableJobContext();
    }

    public static Id getQueueableChainBatchId() {
        return QUEUEABLE_MANAGER_INSTANCE
            .getQueueableChainBatchId();
    }

    public class QueueableJobContext {
        public QueueableJob currentJob;
        public QueueableContext queueableCtx {
            get {
                return currentJob.queueableCtx;
            }
        }
        public FinalizerContext finalizerCtx {
            get {
                return currentJob.finalizerCtx;
            }
        }
    }

    public class AsyncResult {
        public Id salesforceJobId;
        public String customJobId;
        public Boolean isChained;

        public AsyncResult(Id salesforceJobId) {
            this.salesforceJobId = salesforceJobId;
        }

        public AsyncResult(QueueableJob job) {
            this.salesforceJobId = job.salesforceJobId;
            this.customJobId = job.customJobId;
            this.isChained = String.isBlank(salesforceJobId);
        }
    }

    public abstract class QueueableJob implements Queueable, Comparable {
        public Id salesforceJobId;
        public String customJobId;
        public String className;
        public String uniqueName;
        public Integer delay;
        public Integer priority;
        public AsyncOptions asyncOptions;
        public Boolean isProcessed = false;
        public Boolean continueOnJobEnqueueFail = false;
        public Boolean continueOnJobExecuteFail = false;
        public Boolean rollbackOnJobExecuteFail = false;
        public QueueableContext queueableCtx;

        public String parentCustomJobId;
        public FinalizerContext finalizerCtx;
        public Boolean isFinalizer {
            get {
                return String.isNotBlank(parentCustomJobId);
            }
        }
        
        private QueueableChain chain;

        public abstract void work();

        public void execute(QueueableContext ctx) {
            chain.execute(ctx);
        }
        
        public Integer compareTo(Object compareTo) {
            QueueableJob compareToJob = (QueueableJob)compareTo;
            if (isFinalizer && !compareToJob.isFinalizer) {
                return -1;
            }
            if (!isFinalizer && compareToJob.isFinalizer ) {
                return 1;
            }
            if (priority != null && compareToJob.priority == null) {
                return -1;
            }
            if (priority == null && compareToJob.priority != null) {
                return 1;
            }
            if (priority == compareToJob.priority) {
                return 0;
            }
            return priority - compareToJob.priority;     
        }

        public void enqueue(QueueableChain chain) {
            this.chain = chain;
            if (delay != null) {
                salesforceJobId = System.enqueueJob(this, delay);
            } else if (asyncOptions != null) {
                salesforceJobId = System.enqueueJob(this, asyncOptions);
            } else {
                salesforceJobId = System.enqueueJob(this);
            }
        }

        public void setMainAttributes() {
            this.customJobId = UUID.randomUUID().toString();
            this.className = getClassName();
            this.uniqueName = className + '::' + System.now().formatGMT('yyyy-MM-dd\'T\'HH:mm:ss.SSSZ');
        }

        public void setChainCounterToName(Integer chainCounter) {
            this.uniqueName = this.uniqueName + '::' + String.valueOf(chainCounter);
        }

        public void createAsyncResult() {
            insert new AsyncResult__c(
                SalesforceJobId__c = salesforceJobId,
                CustomJobId__c = customJobId,
                Result__c = finalizerCtx.getResult().toString()
            );
        }

        private String getClassName() {
            return String.valueOf(this).substringBefore(':');
        }
    }
    public abstract class QueueableJobAllowsCallouts extends QueueableJob implements Database.AllowsCallouts {
    }

    public abstract class QueueableJobFinalizer extends QueueableJobAllowsCallouts {
    }

    @TestVisible
    private static final QueueableManager QUEUEABLE_MANAGER_INSTANCE = new QueueableManager();
    @TestVisible
    private static final BatchableManager BATCHABLE_MANAGER_INSTANCE = new BatchableManager();
    @TestVisible
    private static final SchedulableManager SCHEDULABLE_MANAGER_INSTANCE = new SchedulableManager();

    private QueueableChain chain;

    @TestVisible
    private static final String QUEUEABLE_JOB_SETTING_ALL = 'All';
    @TestVisible
    private static final String ERROR_MESSAGE_ASYNC_OPTIONS_AFTER_DELAY = 'Cannot set asyncOptions after delay has been set';
    @TestVisible
    private static final String ERROR_MESSAGE_DELAY_AFTER_ASYNC_OPTIONS = 'Cannot set delay after asyncOptions has been set';
    @TestVisible
    private static final String ERROR_MESSAGE_CHAIN_NULL = 'QueueableChain cannot be null';
    @TestVisible
    private static final String ERROR_MESSAGE_NO_JOB_SET = 'No Queueable job has been set to enqueue';
    @TestVisible
    private static final String ERROR_MESSAGE_FINALIZER_JOB_NOT_SET = 'No Finalizer job has been set to attach finalizer';
    @TestVisible
    private static final String ERROR_MESSAGE_CANNOT_ATTACH_FINALIZER = 'Cannot attach finalizer when not in a QueueableChain context';
    @TestVisible
    private static final String ERROR_MESSAGE_CANNOT_ENQUEUE_FINALIZER_DIRECTLY = 'Cannot enqueue a QueueableJob.Finalizer directly. Use attachFinalizer() instead.';
    @TestVisible
    private static final String ERROR_MESSAGE_FINALIZER_JOB_MUST_EXTEND_FINALIZER = 'Finalizer job must extend QueueableJob.Finalizer';
    @TestVisible
    private static final String ERROR_MESSAGE_JOB_NOT_SET = 'Batch job must be set.';
    @TestVisible
    private static  final String ERROR_MESSAGE_JOB_NAME = 'Job name must be set.';
    @TestVisible
    private static  final String ERROR_MESSAGE_CRON_AND_MINUTES_NOT_SET = 'Cron expressions or minutes from now must be set.';
    @TestVisible
    private static  final String ERROR_MESSAGE_CRON_AND_MINUTES_SET = 'Cannot set both cron expressions and minutes from now.';
    @TestVisible
    private static  final String ERROR_MESSAGE_JOB_BATCHABLE = 'Job must be a batch job when using minutes from now.';
    private static final Integer DEFAULT_BATCH_SIZE = 200;

    public class QueueableBuilder implements IQueueableBuilder {
        private QueueableJob job;

        public QueueableBuilder(QueueableJob job) {
            this.job = job;
        }

        public IQueueableBuilder asyncOptions(AsyncOptions asyncOptions) {
            if (job.delay != null) {
                throw new IllegalArgumentException(ERROR_MESSAGE_ASYNC_OPTIONS_AFTER_DELAY);
            }
            job.asyncOptions = asyncOptions;
            return this;
        }

        public IQueueableBuilder delay(Integer delay) {
            if (job.asyncOptions != null) {
                throw new IllegalArgumentException(ERROR_MESSAGE_DELAY_AFTER_ASYNC_OPTIONS);
            }
            job.delay = delay;
            return this;
        }

        public IQueueableBuilder priority(Integer priority) {
            job.priority = priority;
            return this;
        }

        public IQueueableBuilder continueOnJobEnqueueFail() {
            job.continueOnJobEnqueueFail = true;
            return this;
        }

        public IQueueableBuilder continueOnJobExecuteFail() {
            job.continueOnJobExecuteFail = true;
            return this;
        }

        public IQueueableBuilder rollbackOnJobExecuteFail() {
            job.rollbackOnJobExecuteFail = true;
            return this;
        }

        public ISchedulableBuilder asSchedulable() {
            return new SchedulableBuilder(this);
        }

        public AsyncResult attachFinalizer() {
            return QUEUEABLE_MANAGER_INSTANCE.attachFinalizer(job);
        }

        public AsyncResult enqueue() {
            return QUEUEABLE_MANAGER_INSTANCE.enqueue(job);
        }
    }

    @TestVisible
    private class QueueableChain {
        @TestVisible
        private List<QueueableJob> jobs = new List<QueueableJob>();
        @TestVisible
        private Id initialQueuableChainBatchJobId;
        private Boolean isChainedContext = false;
        private Integer chainCounter = 0;
        private QueueableJob currentJob;

        @TestVisible
        private Map<String, QueueableJobSetting__mdt> queueableJobSettingByJobName {
            get {
                if (Test.isRunningTest()) {
                    return queueableJobSettingByJobName ?? new Map<String, QueueableJobSetting__mdt>();
                }
                Map<String, QueueableJobSetting__mdt> jobSettings = new Map<String, QueueableJobSetting__mdt>();
                for (QueueableJobSetting__mdt jobSetting : QueueableJobSetting__mdt.getAll().values()) {
                    jobSettings.put(jobSetting.QueueableJobName__c, jobSetting);
                }
                return jobSettings;
            }
            private set;
        }

        public void execute(QueueableContext ctx) {
            QUEUEABLE_MANAGER_INSTANCE.setChain(this);
            attachQueueableChainFinalizer();
            executeCurrentJob(ctx);
        }

        public void attachQueueableChainFinalizer() {
            System.attachFinalizer(new QueueableChainFinalizer(this));
        }

        public void executeCurrentJob(QueueableContext ctx) {
            if (!hasNextJob()) {
                return;
            }

            currentJob = getNextJobToProcess();
            currentJob.queueableCtx = ctx;
            currentJob.salesforceJobId = ctx.getJobId();
            currentJob.setChainCounterToName(++chainCounter);
            Savepoint sp = currentJob.rollbackOnJobExecuteFail ? Database.setSavepoint() : null;
            try {
                System.debug(currentJob.customJobId);
                System.debug(currentJob.uniqueName);
                currentJob.work();
            } catch (Exception ex) {
                if (!currentJob.continueOnJobExecuteFail) {
                    throw ex;
                }
                if (currentJob.rollbackOnJobExecuteFail) {
                    Database.rollback(sp);
                    Database.releaseSavepoint(sp);
                }
            }
        }

        public void enqueueNextJobIfAnyFromFinalizer(FinalizerContext ctx) {
            QueueableJob previousJob = currentJob;
            previousJob.isProcessed = true;
            previousJob.finalizerCtx = ctx;
            
            createJobResultIfEnabled(previousJob);
            setFinalizerContextToAllFinalizersForPreviousJob(previousJob, ctx);
            enqueueNextJobIfAny();
        }

        public void createJobResultIfEnabled(QueueableJob previousJob) {
            if (queueableJobSettingByJobName.get(QUEUEABLE_JOB_SETTING_ALL)?.CreateResult__c == true
                || queueableJobSettingByJobName.get(previousJob.className)?.CreateResult__c == true
            ) {
                previousJob.createAsyncResult();
            }
        }

        public void enqueueNextJobIfAny() {
            removeJobsThatAreDisabledAndDependentFinalizers();
            if (!hasNextJob() || (Test.isRunningTest() && System.isQueueable())) {
                return;
            }
            
            jobs.sort();
            QueueableJob nextJob = getNextJobToProcess();
            try {
                isChainedContext = true;
                nextJob.enqueue(this);
            } catch (Exception ex) {
                if (!nextJob.continueOnJobEnqueueFail) {
                    throw ex;
                }
                isChainedContext = false;
                nextJob.isProcessed = true;
                enqueueNextJobIfAny();
            }
        }

        public Boolean hasNextJob() {
            return getNextJobToProcess() != null;
        }

        public void addJob(QueueableJob job) {
            job.setMainAttributes();
            jobs.add(job);
        }

        public void executeOrReplaceInitialQueueableChainBatchJob() {
            removeInitialQueuableChainBatchJobIfExists(initialQueuableChainBatchJobId);
            initialQueuableChainBatchJobId = Database.executeBatch(new Async(this));
        }

        public QueueableJob getCurrentJob() {
            return currentJob;
        }

        public Boolean isChainedContext() {
            return isChainedContext;
        }

        public Id getQueueableChainBatchId() {
            return initialQueuableChainBatchJobId;
        }

        @TestVisible
        private void removeJobsThatAreDisabledAndDependentFinalizers() {
            Map<String, QueueableJobSetting__mdt> jobSettings = queueableJobSettingByJobName;

            if (jobSettings.isEmpty()) {
                // If there are no job settings, do not remove any jobs
                return;
            }

            QueueableJobSetting__mdt allJobSetting = jobSettings.get(QUEUEABLE_JOB_SETTING_ALL);

            if(allJobSetting?.IsDisabled__c == true) {
                // If the global setting is disabled, clear all jobs
                jobs.clear();
                return;
            }

            // there are job settings, and if the class is disabled it should be removed and if there is a finalizer that have parentJobId set to this removed job, it should be removed as well, think about creating some logical way to do that, maybe recursion
            Set<String> customJobIdsToRemove = new Set<String>();
            for (QueueableJob job : jobs) {
                QueueableJobSetting__mdt jobSetting = jobSettings.get(job.className);
                if (jobSetting != null && jobSetting.IsDisabled__c) {
                    customJobIdsToRemove.add(job.customJobId);
                }
            }

            // If there are no jobs to remove, return early
            if (customJobIdsToRemove.isEmpty()) {
                return;
            }
            customJobIdsToRemove = getAllCustomJobIdsToRemove(customJobIdsToRemove);
            
            for (Integer i = jobs.size() - 1; i >= 0; i--) {
                QueueableJob job = jobs[i];
                if (customJobIdsToRemove.contains(job.customJobId)) {
                    jobs.remove(i);
                }
            }
        }

        private Set<String> getAllCustomJobIdsToRemove(Set<String> customJobIdsToRemove) {
            Set<String> dependentCustomJobIdsToRemove = new Set<String>();
            for (QueueableJob job : jobs) {
                if (customJobIdsToRemove.contains(job.parentCustomJobId)) {
                    dependentCustomJobIdsToRemove.add(job.customJobId);
                }
            }
            
            if (dependentCustomJobIdsToRemove.isEmpty()) {
                return customJobIdsToRemove;
            } else {
                customJobIdsToRemove.addAll(getAllCustomJobIdsToRemove(dependentCustomJobIdsToRemove));
                return customJobIdsToRemove;
            }
        }

        private QueueableJob getNextJobToProcess() {
            for (QueueableJob job : jobs) {
                if (!job.isProcessed) {
                    return job;
                }
            }
            return null;
        }

        private void setFinalizerContextToAllFinalizersForPreviousJob(QueueableJob previousJob, FinalizerContext ctx) {
            for (QueueableJob job : jobs) {
                if (!job.isProcessed && job.parentCustomJobId == previousJob.customJobId && job.finalizerCtx == null) {
                    job.finalizerCtx = ctx;
                }
            }
        }
    }

    private class QueueableManager {
        private QueueableChain chain = new QueueableChain();

        // Should only be used by QueueableChain to set the chain in the context
        public void setChain(QueueableChain chain) {
            if (chain == null) {
                throw new IllegalArgumentException(ERROR_MESSAGE_CHAIN_NULL);
            }
            this.chain = chain;
        }

        public QueueableJobContext getQueueableJobContext() {
            QueueableJobContext ctx = new QueueableJobContext();
            ctx.currentJob = chain.getCurrentJob();
            return ctx;
        }

        public Id getQueueableChainBatchId() {
            return chain.getQueueableChainBatchId();
        }

        public AsyncResult attachFinalizer(QueueableJob job) {
            if (job == null) {
                throw new IllegalArgumentException(ERROR_MESSAGE_FINALIZER_JOB_NOT_SET);
            }

            if (!chain.isChainedContext()) {
                throw new IllegalArgumentException(ERROR_MESSAGE_CANNOT_ATTACH_FINALIZER);
            }

            QueueableJob currentJobInChainContact = chain.getCurrentJob();
            job.parentCustomJobId = currentJobInChainContact.customJobId;
            
            return enqueue(job);
        }

        public AsyncResult enqueue(QueueableJob job) {
            if (job == null) {
                throw new IllegalArgumentException(ERROR_MESSAGE_NO_JOB_SET);
            }
            if (!job.isFinalizer && job instanceof QueueableJobFinalizer) {
                throw new IllegalArgumentException(ERROR_MESSAGE_CANNOT_ENQUEUE_FINALIZER_DIRECTLY);
            }
            if (job.isFinalizer && !(job instanceof QueueableJobFinalizer)) {
                throw new IllegalArgumentException(ERROR_MESSAGE_FINALIZER_JOB_MUST_EXTEND_FINALIZER);
            }


            chain.addJob(job);
            if (shouldExecuteOrReplaceInitialQueueableChainBatch(job)) {
                chain.executeOrReplaceInitialQueueableChainBatchJob();
            } else if (!chain.isChainedContext()) {
                chain.enqueueNextJobIfAny();
                chain = new QueueableChain();
            }

            AsyncResult result = new AsyncResult(job);
            return result;
        }

        private Boolean shouldExecuteOrReplaceInitialQueueableChainBatch(QueueableJob job) {
            return 
                !chain.isChainedContext() && (
                    Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs() ||
                    System.isQueueable()
                );
        }
    }

    private class QueueableChainFinalizer implements Finalizer {
        private QueueableChain chain;

        public QueueableChainFinalizer(QueueableChain chain) {
            if (chain == null) {
                throw new IllegalArgumentException('QueueableChain cannot be null');
            }
            this.chain = chain;
        }

        public void execute(FinalizerContext ctx) {
            chain.enqueueNextJobIfAnyFromFinalizer(ctx);
        }
    }

    private class QueueableSchedulable implements Schedulable {
        public IQueueableBuilder builder;
        
        public QueueableSchedulable(IQueueableBuilder builder) {
            this.builder = builder;
        }

        public void execute(SchedulableContext scx) {
            builder.enqueue();
        }
    }

    public class BatchableBuilder implements IBatchableBuilder {
        public Database.Batchable<Object> job;
        public Integer scopeSize;
        public Integer minutesFromNow;

        public BatchableBuilder(Object job) {
            this.job = (Database.Batchable<Object>) job;
        }

        public IBatchableBuilder scopeSize(Integer scopeSize) {
            if (scopeSize <= 0) {
                throw new IllegalArgumentException('Scope size must be greater than zero.');
            }
            this.scopeSize = scopeSize;
            return this;
        }

        public IBatchableBuilder minutesFromNow(Integer minutes) {
            if (minutes <= 0) {
                throw new IllegalArgumentException('Minutes from now must be greater than zero.');
            }
            this.minutesFromNow = minutes;
            return this;
        }

        public ISchedulableBuilder asSchedulable() {
            return new SchedulableBuilder(this);
        }

        public AsyncResult execute() {
            return BATCHABLE_MANAGER_INSTANCE.execute(this);
        }
    }

    private class BatchableManager {
        public AsyncResult execute(BatchableBuilder builder) {
            if (builder == null || builder.job == null) {
                throw new IllegalArgumentException('Batch job must be set.');
            }

            Id jobId = Database.executeBatch(builder.job, builder.scopeSize ?? DEFAULT_BATCH_SIZE);

            AsyncResult result = new AsyncResult(jobId);
            return result;
        }
    }

    private class BatchableSchedulable implements Schedulable {
        public IBatchableBuilder builder;
        
        public BatchableSchedulable(IBatchableBuilder builder) {
            this.builder = builder;
        }

        public void execute(SchedulableContext scx) {
            builder.execute();
        }
    }

    public class SchedulableBuilder implements ISchedulableBuilder {
        public Schedulable scheduleJob;
        public String name;
        public List<ICronBuilder> crons = new List<ICronBuilder>();
        public BatchableBuilder batchableBuilder;

        public SchedulableBuilder(QueueableBuilder builder) {
            this.scheduleJob = new QueueableSchedulable(builder);
        }

        public SchedulableBuilder(BatchableBuilder builder) {
            this.batchableBuilder = builder;
            this.scheduleJob = new BatchableSchedulable(builder);
        }

        public SchedulableBuilder(Schedulable scheduleJob) {
            this.scheduleJob = scheduleJob;
        }

        public ISchedulableBuilder name(String name) {
            this.name = name;
            return this;
        }

        public ISchedulableBuilder cronExpression(String cronExpression) {
            this.crons.add(new CronBuilder(cronExpression));
            return this;
        }

        public ISchedulableBuilder cronExpression(ICronBuilder builder) {
            this.crons.add(builder);
            return this;
        }

        public ISchedulableBuilder cronExpression(List<ICronBuilder> builders) {
            this.crons.addAll(builders);
            return this;
        }

        public List<AsyncResult> schedule() {
            return SCHEDULABLE_MANAGER_INSTANCE.schedule(this);
        }
    }

    public class CronBuilder implements ICronBuilder {
        private final String ALL_VALUES = '*';
        private final String INCREMENTS = '/';
        private final String VALUE_DELIMITER = ',';
        private final String DEFAULT_VALUE = ALL_VALUES;
        private final String DEFAULT_SECOND_AND_MINUTE_VALUE = '0';
        private final String DEFAULT_DAY_OF_WEEK_VALUE = '?';
        private final String CRON_EXPRESSION_DELIMITER = ' ';

        public String second;
        public String minute;
        public String hour;
        public String dayOfMonth;
        public String month;
        public String dayOfWeek;
        public String optionalYear;

        public CronBuilder() {}

        public CronBuilder(String cronExpression) {
            if (String.isBlank(cronExpression)) {
                throw new IllegalArgumentException('Cron expression cannot be blank.');
            }

            List<String> parts = cronExpression.split(CRON_EXPRESSION_DELIMITER);
            if (parts.size() != 6 && parts.size() != 7) {
                throw new IllegalArgumentException('Cron expression must have 6 or 7 parts, but was: ' + cronExpression);
            }

            this.second = parts[0];
            this.minute = parts[1];
            this.hour = parts[2];
            this.dayOfMonth = parts[3];
            this.month = parts[4];
            this.dayOfWeek = parts[5];
            this.optionalYear = (parts.size() == 7) ? parts[6] : DEFAULT_VALUE;
        }

        public ICronBuilder second(String second) {
            this.second = second;
            return this;
        }

        public ICronBuilder minute(String minute) {
            this.minute = minute;
            return this;
        }

        public ICronBuilder hour(String hour) {
            this.hour = hour;
            return this;
        }

        public ICronBuilder dayOfMonth(String dayOfMonth) {
            this.dayOfMonth = dayOfMonth;
            return this;
        }

        public ICronBuilder month(String month) {
            this.month = month;
            return this;
        }

        public ICronBuilder dayOfWeek(String dayOfWeek) {
            this.dayOfWeek = dayOfWeek;
            return this;
        }

        public ICronBuilder optionalYear(String optionalYear) {
            this.optionalYear = optionalYear;
            return this;
        }

        public List<ICronBuilder> buildForEveryXMinutes(Integer everyXMinutes) {
            if (everyXMinutes <= 0) {
                throw new IllegalArgumentException('Every X minutes must be greater than zero.');
            }
            if (everyXMinutes > 30) {
                throw new IllegalArgumentException('Every X minutes must be 30 or less.');
            }

            List<CronBuilder> crons = new List<CronBuilder>();
            for (Integer min = 0; min < 60; min += everyXMinutes) {
                this.minute = String.valueOf(min);
                crons.add(new CronBuilder(this.getCronExpression()));
            }
            
            return crons;
        }

        public ICronBuilder everyHour(Integer minute) {
            this.minute = String.valueOf(minute);
            return this;
        }

        public ICronBuilder everyXHours(Integer everyXHours, Integer minute) {
            if (everyXHours <= 0) {
                throw new IllegalArgumentException('Every X hours must be greater than zero.');
            }
            if (everyXHours > 12) {
                throw new IllegalArgumentException('Every X hours must be 12 or less.');
            }

            this.hour = ALL_VALUES + INCREMENTS + everyXHours;
            this.minute = String.valueOf(minute);
            return this;
        }

        public ICronBuilder everyDay(Integer hour, Integer minute) {
            this.hour = String.valueOf(hour);
            this.minute = String.valueOf(minute);
            return this;
        }

        public ICronBuilder everyXDays(Integer everyXDays, Integer hour, Integer minute) {
            if (everyXDays <= 0) {
                throw new IllegalArgumentException('Every X days must be greater than zero.');
            }
            if (everyXDays > 15) {
                throw new IllegalArgumentException('Every X days must be 15 or less.');
            }

            this.dayOfMonth = ALL_VALUES + INCREMENTS + everyXDays;
            this.hour = String.valueOf(hour);
            this.minute = String.valueOf(minute);
            return this;
        }

        public ICronBuilder everyMonth(Integer day, Integer hour, Integer minute) {
            this.dayOfMonth = String.valueOf(day);
            this.hour = String.valueOf(hour);
            this.minute = String.valueOf(minute);
            return this;
        }

        public ICronBuilder everyXMonths(Integer everyXMonths, Integer dayOfMonth, Integer hour, Integer minute) {
            if (everyXMonths <= 0) {
                throw new IllegalArgumentException('Every X months must be greater than zero.');
            }
            if (everyXMonths > 6) {
                throw new IllegalArgumentException('Every X months must be 6 or less.');
            }

            this.month = ALL_VALUES + INCREMENTS + everyXMonths;
            this.dayOfMonth = String.valueOf(dayOfMonth);
            this.hour = String.valueOf(hour);
            this.minute = String.valueOf(minute);
            return this;
        }

        public String getCronExpression() {
            return String.join(new List<String>{
                    second ?? DEFAULT_SECOND_AND_MINUTE_VALUE,
                    minute ?? DEFAULT_SECOND_AND_MINUTE_VALUE,
                    hour ?? DEFAULT_VALUE,
                    dayOfMonth ?? DEFAULT_VALUE,
                    month ?? DEFAULT_VALUE,
                    dayOfWeek ?? DEFAULT_DAY_OF_WEEK_VALUE,
                    optionalYear ?? DEFAULT_VALUE
                }, CRON_EXPRESSION_DELIMITER);
        }
    }

    private class SchedulableManager {
        public List<AsyncResult> schedule(SchedulableBuilder builder) {
            if (builder == null || builder.scheduleJob == null) {
                throw new IllegalArgumentException(ERROR_MESSAGE_JOB_NOT_SET);
            }
            if (String.isBlank(builder.name)) {
                throw new IllegalArgumentException(ERROR_MESSAGE_JOB_NAME);
            }
            if ((builder.crons == null || builder.crons.isEmpty()) && builder.batchableBuilder?.minutesFromNow == null) {
                throw new IllegalArgumentException(ERROR_MESSAGE_CRON_AND_MINUTES_NOT_SET);
            }
            if ((builder.crons != null && !builder.crons.isEmpty()) && builder.batchableBuilder?.minutesFromNow != null) {
                throw new IllegalArgumentException(ERROR_MESSAGE_CRON_AND_MINUTES_SET);
            }
            
            List<AsyncResult> results = new List<AsyncResult>();
            if (builder.batchableBuilder?.minutesFromNow != null) {
                results.add(
                    new AsyncResult(
                        System.scheduleBatch(
                            builder.batchableBuilder.job, 
                            builder.name, 
                            builder.batchableBuilder.minutesFromNow, 
                            builder.batchableBuilder.scopeSize ?? DEFAULT_BATCH_SIZE
                        )
                    )
                );
            } else {
                for (Integer i = 0; i < builder.crons.size(); i++) {
                    ICronBuilder cron = builder.crons[i];
                    results.add(
                        new AsyncResult(
                            System.schedule(
                                builder.name + (builder.crons.size() == 1 ? '' : '/' + i),
                                cron.getCronExpression(),
                                builder.scheduleJob
                            )
                        )
                    );
                }
            }

            return results;
        }
    }

    private Async(QueueableChain chain) {
        if (chain == null) {
            throw new IllegalArgumentException('QueueableChain cannot be null');
        }
        this.chain = chain;
    }

    public Iterable<Account> start(Database.BatchableContext bc){
        // This is just a placeholder to start the batch.
        return new List<Account>{ new Account() };
    }

    public void execute(Database.BatchableContext bc, List<Account> scope){
        chain.enqueueNextJobIfAny();
    }

    public void finish(Database.BatchableContext bc){
    }

    private static void removeInitialQueuableChainBatchJobIfExists(Id jobId) {
        if (jobId == null) {
            return;
        }

        try {
            System.abortJob(jobId);
        } catch (Exception e) {
            // No action if not exists
        }
    }
}
