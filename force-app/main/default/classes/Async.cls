/**
 * Copyright (c) 2025 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
**/
public inherited sharing class Async {
    // public interface QueueableBuilder {
    //     QueueableBuilder asyncOptions(AsyncOptions asyncOptions);
    //     QueueableBuilder delay(Integer delay);
    //     QueueableBuilder priority(Integer priority);
    //     QueueableBuilder continueOnJobEnqueueFail();
    //     QueueableBuilder continueOnJobExecuteFail();
    //     QueueableBuilder rollbackOnJobExecuteFail();
    //     SchedulableBuilder asSchedulable();
    //     AsyncResult attachFinalizer();
    //     AsyncResult enqueue();
    // }

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

    private static final BatchableManager BATCHABLE_MANAGER_INSTANCE = new BatchableManager();
    private static final SchedulableManager SCHEDULABLE_MANAGER_INSTANCE = new SchedulableManager();
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

    public static QueueableBuilder queueable(QueueableJob job) {
        return new QueueableBuilder(job);
    }

    public static IBatchableBuilder batchable(Object job) {
        return new BatchableBuilder(job); 
    }

    public static ISchedulableBuilder schedulable(Schedulable scheduleJob) {
        return new SchedulableBuilder(scheduleJob);
    }

    public static QueueableJobContext getQueueableJobContext() {
        return QueueableManager.get()
            .getQueueableJobContext();
    }

    public static Id getQueueableChainBatchId() {
        return QueueableManager.get()
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

    public class BatchableManager {
        public AsyncResult execute(BatchableBuilder builder) {
            if (builder == null || builder.job == null) {
                throw new IllegalArgumentException('Batch job must be set.');
            }

            Id jobId = Database.executeBatch(builder.job, builder.scopeSize ?? DEFAULT_BATCH_SIZE);

            AsyncResult result = new AsyncResult(jobId);
            return result;
        }
    }

    public class BatchableSchedulable implements Schedulable {
        public BatchableBuilder builder;
        
        public BatchableSchedulable(BatchableBuilder builder) {
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

    @TestVisible
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
}
