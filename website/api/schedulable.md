# Schedulable API

Apex classes `SchedulableBuilder.cls`, `SchedulableManager.cls`, and `CronBuilder.cls`.

Common Schedulable example:

```apex
Schedulable job = new MySchedulableJob();
List<Async.AsyncResult> results = Async.schedulable(job)
	.name('Daily Processing Job')
	.cronExpression('0 0 2 * * ? *')
	.skipWhenAlreadyScheduled()
	.schedule();
System.debug('Scheduled job results: ' + results);
```

## Methods

The following are methods for using Async with Schedulable jobs:

[**INIT**](#init)

- [`schedulable(Schedulable scheduleJob)`](#schedulable)

[**Build - Schedulable**](#build---schedulable)

- [`name(String name)`](#name)
- [`cronExpression(String cronExpression)`](#cronexpression)
- [`cronExpression(CronBuilder builder)`](#cronexpression-1)
- [`cronExpression(List<CronBuilder> builders)`](#cronexpression-2)
- [`skipWhenAlreadyScheduled()`]()

[**Build - Cron Expression**](#build---cron-expression)

- [`second(String second)`](#second)
- [`minute(String minute)`](#minute)  
- [`hour(String hour)`](#hour)
- [`dayOfMonth(String dayOfMonth)`](#dayofmonth)
- [`month(String month)`](#month)
- [`dayOfWeek(String dayOfWeek)`](#dayofweek)
- [`optionalYear(String optionalYear)`](#optionalyear)
- [`buildForEveryXMinutes(Integer everyXMinutes)`](#buildforeveryxminutes)
- [`everyHour(Integer minute)`](#everyhour)
- [`everyXHours(Integer everyXHours, Integer minute)`](#everyxhours)
- [`everyDay(Integer hour, Integer minute)`](#everyday)
- [`everyXDays(Integer everyXDays, Integer hour, Integer minute)`](#everyxdays)
- [`everyMonth(Integer day, Integer hour, Integer minute)`](#everymonth)
- [`everyXMonths(Integer everyXMonths, Integer dayOfMonth, Integer hour, Integer minute)`](#everyxmonths)
- [`getCronExpression()`](#getcronexpression)


[**Schedule**](#schedule)

- [`schedule()`](#schedule)

### INIT

#### schedulable

Constructs a new SchedulableBuilder instance with the specified schedulable job.

**Signature**

```apex
Async schedulable(Schedulable scheduleJob);
```

**Strict Example**

```apex
Async.schedulable(new MySchedulableJob());
```

**Batchable Conversion Example**

```apex
Async.batchable(new MyBatchJob())
	.asSchedulable();
```

**Queueable Conversion Example**

```apex
Async.queueable(new MyQueueableJob())
	.asSchedulable();
```

### Build - Schedulable

#### name

Sets the name for the scheduled job. This is required for scheduling.

**Signature**

```apex
SchedulableBuilder name(String name);
```

**Example**

```apex
Async.schedulable(new MySchedulableJob())
	.name('Daily Cleanup Job');
```

#### cronExpression string

Sets a cron expression for scheduling the job. Can be called multiple times to schedule at different intervals.

**Signature**

```apex
SchedulableBuilder cronExpression(String cronExpression);
```

**Example**

```apex
Async.schedulable(new MySchedulableJob())
	.name('Hourly Job')
	.cronExpression('0 0 * * * ? *');
```

#### cronExpression builder

Sets a cron expression using a CronBuilder for more advanced scheduling configuration.

**Signature**

```apex
SchedulableBuilder cronExpression(CronBuilder builder);
```

**Example**

```apex
CronBuilder cron = new CronBuilder().everyHour(1);
Async.schedulable(new MySchedulableJob())
	.name('Nightly Job')
	.cronExpression(cron);
```

#### cronExpression multiple builders

Sets multiple cron expressions using a list of CronBuilder instances for complex scheduling scenarios.

**Signature**

```apex
SchedulableBuilder cronExpression(List<CronBuilder> builders);
```

**Example**

```apex
List<CronBuilder> crons = new List<CronBuilder>{
	new CronBuilder().everyHour(0),
	new CronBuilder().everyDay(0, 0)
};
Async.schedulable(new MySchedulableJob())
	.name('Business Hours Job')
	.cronExpression(crons);
```

#### skipWhenAlreadyScheduled

If set, the job will not be scheduled if it is already scheduled with the same name. This prevents throwing the `System.AsyncException`.

**Signature**

```apex
SchedulableBuilder skipWhenAlreadyScheduled();
```

**Example**

```apex
Async.schedulable(new MySchedulableJob())
	.skipWhenAlreadyScheduled();
```

### Build - Cron Expression

#### second

Sets the second value for the cron expression (0-59).

**Signature**

```apex
CronBuilder second(String second);
```

**Example**

```apex
CronBuilder cron = new CronBuilder()
	.second('30')
	.minute('0')
	.hour('12');
```

#### minute

Sets the minute value for the cron expression (0-59).

**Signature**

```apex
CronBuilder minute(String minute);
```

**Example**

```apex
CronBuilder cron = new CronBuilder()
	.minute('15')
	.hour('10');
```

#### hour

Sets the hour value for the cron expression (0-23).

**Signature**

```apex
CronBuilder hour(String hour);
```

**Example**

```apex
CronBuilder cron = new CronBuilder()
	.hour('14')
	.minute('0');
```

#### dayOfMonth

Sets the day of month value for the cron expression (1-31).

**Signature**

```apex
CronBuilder dayOfMonth(String dayOfMonth);
```

**Example**

```apex
CronBuilder cron = new CronBuilder()
	.dayOfMonth('15')
	.hour('9');
```

#### month

Sets the month value for the cron expression (1-12).

**Signature**

```apex
CronBuilder month(String month);
```

**Example**

```apex
CronBuilder cron = new CronBuilder()
	.month('6')
	.dayOfMonth('1');
```

#### dayOfWeek

Sets the day of week value for the cron expression (1-7, where 1=Sunday).

**Signature**

```apex
CronBuilder dayOfWeek(String dayOfWeek);
```

**Example**

```apex
CronBuilder cron = new CronBuilder()
	.dayOfWeek('2')  // Monday
	.hour('9');
```

#### optionalYear

Sets the optional year value for the cron expression.

**Signature**

```apex
CronBuilder optionalYear(String optionalYear);
```

**Example**

```apex
CronBuilder cron = new CronBuilder()
	.optionalYear('2024')
	.hour('12');
```

#### buildForEveryXMinutes

Creates multiple CronBuilder instances for execution every X minutes (max 30 minutes).

**Signature**

```apex
List<CronBuilder> buildForEveryXMinutes(Integer everyXMinutes);
```

**Example**

```apex
CronBuilder baseCron = new CronBuilder().hour('9');
List<CronBuilder> crons = baseCron.buildForEveryXMinutes(15);
// Runs every 15 minutes during hour 9
```

#### everyHour

Sets the cron to run every hour at the specified minute.

**Signature**

```apex
CronBuilder everyHour(Integer minute);
```

**Example**

```apex
CronBuilder cron = new CronBuilder()
	.everyHour(30);  // Run at 30 minutes past every hour
```

#### everyXHours

Sets the cron to run every X hours at the specified minute (max 12 hours).

**Signature**

```apex
CronBuilder everyXHours(Integer everyXHours, Integer minute);
```

**Example**

```apex
CronBuilder cron = new CronBuilder()
	.everyXHours(4, 0);  // Run every 4 hours at minute 0
```

#### everyDay

Sets the cron to run every day at the specified hour and minute.

**Signature**

```apex
CronBuilder everyDay(Integer hour, Integer minute);
```

**Example**

```apex
CronBuilder cron = new CronBuilder()
	.everyDay(14, 30);  // Run daily at 2:30 PM
```

#### everyXDays

Sets the cron to run every X days at the specified hour and minute (max 15 days).

**Signature**

```apex
CronBuilder everyXDays(Integer everyXDays, Integer hour, Integer minute);
```

**Example**

```apex
CronBuilder cron = new CronBuilder()
	.everyXDays(3, 9, 0);  // Run every 3 days at 9:00 AM
```

#### everyMonth

Sets the cron to run every month on the specified day, hour, and minute.

**Signature**

```apex
CronBuilder everyMonth(Integer day, Integer hour, Integer minute);
```

**Example**

```apex
CronBuilder cron = new CronBuilder()
	.everyMonth(1, 2, 0);  // Run on 1st of every month at 2:00 AM
```

#### everyXMonths

Sets the cron to run every X months on the specified day, hour, and minute (max 6 months).

**Signature**

```apex
CronBuilder everyXMonths(Integer everyXMonths, Integer dayOfMonth, Integer hour, Integer minute);
```

**Example**

```apex
CronBuilder cron = new CronBuilder()
	.everyXMonths(3, 15, 10, 30);  // Run every 3 months on 15th at 10:30 AM
```

#### getCronExpression

Returns the complete cron expression string.

**Signature**

```apex
String getCronExpression();
```

**Example**

```apex
CronBuilder cron = new CronBuilder()
	.everyDay(14, 0);
String cronExpr = cron.getCronExpression();
// Returns: "0 0 14 * * ? *"
```

### Schedule

#### schedule

Schedules the job with the configured options. Returns a list of Async.AsyncResult objects (one per cron expression).

**Signature**

```apex
List<Async.AsyncResult> schedule();
```

**Example**

```apex
List<Async.AsyncResult> results = Async.schedulable(new MySchedulableJob())
	.name('Every Hour Processing')
	.cronExpression(
            new CronBuilder()
                .everyHour(1)
        )
	.schedule();
```