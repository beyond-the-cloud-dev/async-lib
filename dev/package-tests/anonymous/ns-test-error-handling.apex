public class ErrorTestSchedulable implements Schedulable {
    public void execute(SchedulableContext sc) {
    }
}

Boolean caught1 = false;
try {
    btcdev.Async.schedulable(new ErrorTestSchedulable())
        .cronExpression(new btcdev.CronBuilder().everyDay(10, 0))
        .schedule();
} catch (Exception e) {
    caught1 = true;
    System.assertNotEquals(null, e.getMessage());
}
System.assert(caught1, 'Should throw for missing schedule name');

Boolean caught2 = false;
try {
    btcdev.Async.schedulable(new ErrorTestSchedulable())
        .name('ErrorTest')
        .schedule();
} catch (Exception e) {
    caught2 = true;
    System.assertNotEquals(null, e.getMessage());
}
System.assert(caught2, 'Should throw for missing cron expression');

Boolean caught3 = false;
try {
    new btcdev.CronBuilder().buildForEveryXMinutes(50);
} catch (Exception e) {
    caught3 = true;
}
System.assert(caught3, 'Should throw for everyXMinutes exceeding 30');

Boolean caught4 = false;
try {
    btcdev.Async.batchable(new NsTestBatch()).scopeSize(0).execute();
} catch (Exception e) {
    caught4 = true;
}
System.assert(caught4, 'Should throw for batch scope size <= 0');

Boolean caught5 = false;
try {
    new btcdev.CronBuilder('invalid');
} catch (Exception e) {
    caught5 = true;
}
System.assert(caught5, 'Should throw for invalid cron expression string');

System.debug('PASS: ns-test-error-handling');
