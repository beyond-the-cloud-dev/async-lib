btcdev.CronBuilder cron1 = new btcdev.CronBuilder().everyHour(30);
System.assertEquals('0 30 * * * ? *', cron1.getCronExpression());

btcdev.CronBuilder cron2 = new btcdev.CronBuilder().everyDay(14, 0);
System.assertEquals('0 0 14 * * ? *', cron2.getCronExpression());

btcdev.CronBuilder cron3 = new btcdev.CronBuilder().everyMonth(1, 9, 0);
System.assertEquals('0 0 9 1 * ? *', cron3.getCronExpression());

btcdev.CronBuilder cron4 = new btcdev.CronBuilder().everyXHours(2, 15);
System.assertNotEquals(null, cron4.getCronExpression());

btcdev.CronBuilder cron5 = new btcdev.CronBuilder().everyXDays(3, 8, 0);
System.assertNotEquals(null, cron5.getCronExpression());

btcdev.CronBuilder cron6 = new btcdev.CronBuilder().everyXMonths(2, 15, 10, 30);
System.assertNotEquals(null, cron6.getCronExpression());

List<btcdev.CronBuilder> crons = new btcdev.CronBuilder().buildForEveryXMinutes(15);
System.assertNotEquals(null, crons);
System.assert(!crons.isEmpty());
for (btcdev.CronBuilder c : crons) {
    System.assertNotEquals(null, c.getCronExpression());
}

btcdev.CronBuilder cronFromString = new btcdev.CronBuilder('0 0 12 * * ?');
System.assertNotEquals(null, cronFromString.getCronExpression());

btcdev.CronBuilder cronManual = new btcdev.CronBuilder()
    .second('0')
    .minute('0')
    .hour('12')
    .dayOfMonth('*')
    .month('*')
    .dayOfWeek('?');
System.assertEquals('0 0 12 * * ? *', cronManual.getCronExpression());

System.debug('PASS: ns-test-cron-builder');
