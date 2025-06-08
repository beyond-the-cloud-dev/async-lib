public class CronBuilder {
    private static final String ALL_VALUES = '*';
    private static final String INCREMENTS = '/';
    private static final String VALUE_DELIMITER = ',';
    private static final String DEFAULT_VALUE = ALL_VALUES;
    private static final String DEFAULT_SECOND_AND_MINUTE_VALUE = '0';
    private static final String DEFAULT_DAY_OF_WEEK_VALUE = '?';
    private static final String CRON_EXPRESSION_DELIMITER = ' ';

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
            throw new Async.IllegalArgumentException('Cron expression cannot be blank.');
        }

        List<String> parts = cronExpression.split(CRON_EXPRESSION_DELIMITER);
        if (parts.size() != 6 && parts.size() != 7) {
            throw new Async.IllegalArgumentException('Cron expression must have 6 or 7 parts, but was: ' + cronExpression);
        }

        this.second = parts[0];
        this.minute = parts[1];
        this.hour = parts[2];
        this.dayOfMonth = parts[3];
        this.month = parts[4];
        this.dayOfWeek = parts[5];
        this.optionalYear = (parts.size() == 7) ? parts[6] : DEFAULT_VALUE;
    }

    public CronBuilder second(String second) {
        this.second = second;
        return this;
    }

    public CronBuilder minute(String minute) {
        this.minute = minute;
        return this;
    }

    public CronBuilder hour(String hour) {
        this.hour = hour;
        return this;
    }

    public CronBuilder dayOfMonth(String dayOfMonth) {
        this.dayOfMonth = dayOfMonth;
        return this;
    }

    public CronBuilder month(String month) {
        this.month = month;
        return this;
    }

    public CronBuilder dayOfWeek(String dayOfWeek) {
        this.dayOfWeek = dayOfWeek;
        return this;
    }

    public CronBuilder optionalYear(String optionalYear) {
        this.optionalYear = optionalYear;
        return this;
    }

    public List<CronBuilder> buildForEveryXMinutes(Integer everyXMinutes) {
        if (everyXMinutes <= 0) {
            throw new Async.IllegalArgumentException('Every X minutes must be greater than zero.');
        }
        if (everyXMinutes > 30) {
            throw new Async.IllegalArgumentException('Every X minutes must be 30 or less.');
        }

        List<CronBuilder> crons = new List<CronBuilder>();
        for (Integer min = 0; min < 60; min += everyXMinutes) {
            this.minute = String.valueOf(min);
            crons.add(new CronBuilder(this.getCronExpression()));
        }
        
        return crons;
    }

    public CronBuilder everyHour(Integer minute) {
        this.minute = String.valueOf(minute);
        return this;
    }

    public CronBuilder everyXHours(Integer everyXHours, Integer minute) {
        if (everyXHours <= 0) {
            throw new Async.IllegalArgumentException('Every X hours must be greater than zero.');
        }
        if (everyXHours > 12) {
            throw new Async.IllegalArgumentException('Every X hours must be 12 or less.');
        }

        this.hour = ALL_VALUES + INCREMENTS + everyXHours;
        this.minute = String.valueOf(minute);
        return this;
    }

    public CronBuilder everyDay(Integer hour, Integer minute) {
        this.hour = String.valueOf(hour);
        this.minute = String.valueOf(minute);
        return this;
    }

    public CronBuilder everyXDays(Integer everyXDays, Integer hour, Integer minute) {
        if (everyXDays <= 0) {
            throw new Async.IllegalArgumentException('Every X days must be greater than zero.');
        }
        if (everyXDays > 15) {
            throw new Async.IllegalArgumentException('Every X days must be 15 or less.');
        }

        this.dayOfMonth = ALL_VALUES + INCREMENTS + everyXDays;
        this.hour = String.valueOf(hour);
        this.minute = String.valueOf(minute);
        return this;
    }

    public CronBuilder everyMonth(Integer day, Integer hour, Integer minute) {
        this.dayOfMonth = String.valueOf(day);
        this.hour = String.valueOf(hour);
        this.minute = String.valueOf(minute);
        return this;
    }

    public CronBuilder everyXMonths(Integer everyXMonths, Integer dayOfMonth, Integer hour, Integer minute) {
        if (everyXMonths <= 0) {
            throw new Async.IllegalArgumentException('Every X months must be greater than zero.');
        }
        if (everyXMonths > 6) {
            throw new Async.IllegalArgumentException('Every X months must be 6 or less.');
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