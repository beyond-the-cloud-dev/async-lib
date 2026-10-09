/**
 * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
 *
 * v3.0.0
 **/
public class NsTestScheduleVerifyJob extends btcdev.QueueableJob {
    public override void work() {
        insert new Task(
            Subject = 'ScheduleVerify - ' + Datetime.now().formatGMT('yyyy-MM-dd HH:mm:ss'),
            Status = 'Completed',
            Priority = 'Low',
            Description = 'Created by NsTestScheduleVerifyJob to verify scheduled queueable execution.'
        );
    }
}
