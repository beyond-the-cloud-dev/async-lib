/**
 * PMD False Positives:
 * - ApexAssertionsShouldIncludeMessage: IMO not all assertions need a message
 * - EmptyStatementBlock: It is test class, some methods are just to create jobs placeholders
**/
@SuppressWarnings('PMD.ApexAssertionsShouldIncludeMessage,PMD.EmptyStatementBlock')
@IsTest
@TestVisible
private class AsyncTest implements Database.Batchable<SObject> {
    private static final String ACCOUNT_NAME = 'Test Account';
    private static final String CUSTOM_ERROR_MESSAGE = 'Something goes wrong.';
    private static final String DUPLICATE_SIGNATURE_ERROR_MESSAGE = 'Attempt to enqueue job with duplicate queueable signature';
    private static final String TEST_SIGNATURE_NAME = 'SignatureName';
    private static final String TEST_SCHEDULABLE_JOB_NAME = 'SchedulableTestJob';

    @IsTest
    private static void shouldEnqueue60QueueablesSuccessfully() {
        SuccessfulQueueableTest q = new SuccessfulQueueableTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Account]);
        Id initialQueuableChainBatchJobId;

        Test.startTest();
        for (Integer idx = 0; idx < 60; idx++) {
            Async.AsyncResult ar = Async.queueable(q).enqueue();
            if (Limits.getQueueableJobs() <= Limits.getLimitQueueableJobs()) {
                Assert.isFalse(ar.isChained, 'Should not be enqueued via batch.');
            } else {
                Assert.isTrue(ar.isChained, 'Should be enqueued via batch.');
            }
        }
        initialQueuableChainBatchJobId = Async.getQueueableChainBatchId();
        Test.stopTest();

        Assert.areEqual(50, [SELECT COUNT() FROM Account], 'Should have 50 job runs (50 queueable and 1 scheduled batch that was not executed yet).');
        List<CronTrigger> cronTriggers = [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name LIKE 'QueueableChainBatch%'];
        Assert.areEqual(
            1,
            cronTriggers.size(),
            'Should schedule only one batchable job with the rest.'
        );
        Assert.areEqual(
            initialQueuableChainBatchJobId,
            cronTriggers[0].Id,
            'The one scheduled batch job should have the same Id as the one returned from Async.getQueueableChainBatchId()'
        );
    }

    @IsTest
    private static void shouldEnqueue60QueueablesWitDelaySuccessfully() {
        SuccessfulQueueableTest q = new SuccessfulQueueableTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Account]);
        Id initialQueuableChainBatchJobId;

        Test.startTest();
        for (Integer idx = 0; idx < 60; idx++) {
            Async.queueable(q)
                .delay(1)
                .enqueue();
        }
        initialQueuableChainBatchJobId = Async.getQueueableChainBatchId();
        Test.stopTest();

        Assert.areEqual(50, [SELECT COUNT() FROM Account], 'Should have 50 job runs (50 queueable and 1 scheduled batch that was not executed yet).');
        List<CronTrigger> cronTriggers = [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name LIKE 'QueueableChainBatch%'];
        Assert.areEqual(
            1,
            cronTriggers.size(),
            'Should schedule only one batchable job with the rest.'
        );
        Assert.areEqual(
            initialQueuableChainBatchJobId,
            cronTriggers[0].Id,
            'The one scheduled batch job should have the same Id as the one returned from Async.getQueueableChainBatchId()'
        );
    }

    @IsTest
    private static void shouldEnqueue60QueueablesSuccessfullyWithAllItemsFailedWithRollback() {
        FailureQueueableTest q = new FailureQueueableTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Account]);
        Id initialQueuableChainBatchJobId;

        Test.startTest();
        for (Integer idx = 0; idx < 60; idx++) {
            Async.queueable(q)
                .continueOnJobExecuteFail()
                .rollbackOnJobExecuteFail()
                .enqueue();
        }
        initialQueuableChainBatchJobId = Async.getQueueableChainBatchId();
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Account], 'Should have no Accounts created.');
        List<CronTrigger> cronTriggers = [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name LIKE 'QueueableChainBatch%'];
        Assert.areEqual(
            1,
            cronTriggers.size(),
            'Should schedule only one batchable job with the rest.'
        );
        Assert.areEqual(
            initialQueuableChainBatchJobId,
            cronTriggers[0].Id,
            'The one scheduled batch job should have the same Id as the one returned from Async.getQueueableChainBatchId()'
        );
    }

    @IsTest
    private static void shouldEnqueue60QueueablesSuccessfullyWithAllItemsFailedWithoutRollback() {
        FailureQueueableTest q = new FailureQueueableTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Account]);
        Id initialQueuableChainBatchJobId;

        Test.startTest();
        for (Integer idx = 0; idx < 60; idx++) {
            Async.queueable(q)
                .continueOnJobExecuteFail()
                .enqueue();
        }
        initialQueuableChainBatchJobId = Async.getQueueableChainBatchId();
        Test.stopTest();

        Assert.areEqual(50, [SELECT COUNT() FROM Account], 'Inserted Accounts are not rollbacked.');
        List<CronTrigger> cronTriggers = [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name LIKE 'QueueableChainBatch%'];
        Assert.areEqual(
            1,
            cronTriggers.size(),
            'Should schedule only one batchable job with the rest.'
        );
        Assert.areEqual(
            initialQueuableChainBatchJobId,
            cronTriggers[0].Id,
            'The one scheduled batch job should have the same Id as the one returned from Async.getQueueableChainBatchId()'
        );
    }

    @IsTest
    private static void shouldOnlyEnqueueOneJobDueToAsyncOptions() {
        SuccessfulQueueableTest q = new SuccessfulQueueableTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Account]);
        AsyncOptions options = new AsyncOptions();
        options.DuplicateSignature = QueueableDuplicateSignature.Builder().addString(TEST_SIGNATURE_NAME).build();

        Test.startTest();
        for (Integer idx = 0; idx < 50; idx++) {
            Async.queueable(q)
                .asyncOptions(options)
                .continueOnJobEnqueueFail()
                .enqueue();
        }
        Test.stopTest();

        Assert.areEqual(1, [SELECT COUNT() FROM Account], 'Only one job should run.');
    }

    @IsTest
    private static void shouldFailJobOnDuplicateAsyncOptionsSignature() {
        SuccessfulQueueableTest q = new SuccessfulQueueableTest();

        AsyncOptions options = new AsyncOptions();
        options.DuplicateSignature = QueueableDuplicateSignature.Builder().addString(TEST_SIGNATURE_NAME).build();

        Test.startTest();
        try {
            Async.queueable(q)
                .asyncOptions(options)
                .enqueue();
            Async.queueable(q)
                .asyncOptions(options)
                .enqueue();
            Assert.fail('Should throw duplicate signature exception.');
        } catch (Exception ex) {
            Assert.areEqual(DUPLICATE_SIGNATURE_ERROR_MESSAGE, ex.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    private static void shouldFailJobDueToExecuteFailure() {
        FailureQueueableTest failureJob = new FailureQueueableTest();

        try {
            Test.startTest();
            Async.queueable(failureJob)
                .enqueue();
            Test.stopTest();
            Assert.fail('Should throw duplicate signature exception.');
        } catch (Exception ex) {
            Assert.areEqual(CUSTOM_ERROR_MESSAGE, ex.getMessage());
        }
    }

    @IsTest
    private static void shouldFailToAttachFinalizerInNonChainContext() {
        QueueableTestFinalizer finalizer = new QueueableTestFinalizer();

        try {
            Test.startTest();
            Async.queueable(finalizer)
                .attachFinalizer();
            Test.stopTest();
            Assert.fail('Should throw exception when trying to attach finalizer in non-chain context.');
        } catch (Exception ex) {
            Assert.areEqual(QueueableManager.ERROR_MESSAGE_CANNOT_ATTACH_FINALIZER, ex.getMessage());
        }
    }

    @IsTest
    private static void shouldFailToEnqueueFinalizerDirectlyByEnqueueMethod() {
        QueueableTestFinalizer finalizer = new QueueableTestFinalizer();

        try {
            Test.startTest();
            Async.queueable(finalizer)
                .enqueue();
            Test.stopTest();
            Assert.fail('Should throw exception when trying to enqueue finalizer directly.');
        } catch (Exception ex) {
            Assert.areEqual(QueueableManager.ERROR_MESSAGE_CANNOT_ENQUEUE_FINALIZER_DIRECTLY, ex.getMessage());
        }
    }

    @IsTest
    private static void shouldFailToAttachFinalizerWhenQueueableJobIsNotFinalizer() {
        FinalizerErrorQueueableTest q = new FinalizerErrorQueueableTest();

        try {
            Test.startTest();
            Async.queueable(q)
                .enqueue();
            Test.stopTest();
            Assert.fail('Should throw exception when trying to attach finalizer to a non-finalizer job.');
        } catch (Exception ex) {
            Assert.areEqual(QueueableManager.ERROR_MESSAGE_FINALIZER_JOB_MUST_EXTEND_FINALIZER, ex.getMessage());
        }
    }

    @IsTest
    private static void shouldSortJobsProperly() {
        QueueableJobTest1 job1 = new QueueableJobTest1();
        job1.uniqueName = 'job1';
        job1.priority = 100;
        QueueableJobTest2 job2 = new QueueableJobTest2();
        job2.uniqueName = 'job2';
        job2.priority = 50;
        QueueableJobTest3 job3 = new QueueableJobTest3();
        job3.uniqueName = 'job3';
        job3.priority = 15;
        QueueableJobTest4 job4 = new QueueableJobTest4();
        job4.uniqueName = 'job4';
        job4.priority = 50;
        QueueableJobTest5 job5 = new QueueableJobTest5();
        job5.uniqueName = 'job5';
        QueueableJobTest6 job6 = new QueueableJobTest6();
        job6.uniqueName = 'job6';
        job6.parentCustomJobId = 'something';
        QueueableJobTest7 job7 = new QueueableJobTest7();
        job7.uniqueName = 'job7';
        job7.parentCustomJobId = 'something';
        job7.priority = 15;
        QueueableJobTest8 job8 = new QueueableJobTest8();
        job8.uniqueName = 'job8';
        job8.parentCustomJobId = 'something';
        job8.priority = 2;

        List<QueueableJob> jobs = new List<QueueableJob>{
            job1,
            job2,
            job3,
            job4,
            job5,
            job6,
            job7,
            job8
        };
        jobs.sort();
        Assert.areEqual('job8', jobs[0].uniqueName);
        Assert.areEqual('job7', jobs[1].uniqueName);
        Assert.areEqual('job6', jobs[2].uniqueName);
        Assert.areEqual('job3', jobs[3].uniqueName);
        Assert.areEqual('job2', jobs[4].uniqueName);
        Assert.areEqual('job4', jobs[5].uniqueName);
        Assert.areEqual('job1', jobs[6].uniqueName);
        Assert.areEqual('job5', jobs[7].uniqueName);
    }

    @IsTest
    private static void shouldRemoveAllDisabledJobs() {
        QueueableJobTest1 job1 = new QueueableJobTest1();
        job1.uniqueName = 'job1';
        QueueableJobTest2 job2 = new QueueableJobTest2();
        job2.uniqueName = 'job2';
        QueueableJobTest3 job3 = new QueueableJobTest3();
        job3.uniqueName = 'job3';

        QueueableChain chain = new QueueableChain();
        chain.queueableJobSettingByJobName = new Map<String, QueueableJobSetting__mdt>{
            QueueableManager.QUEUEABLE_JOB_SETTING_ALL => new QueueableJobSetting__mdt(
                DeveloperName = QueueableManager.QUEUEABLE_JOB_SETTING_ALL,
                IsDisabled__c = true
            )
        };
        chain.addJob(job1);
        chain.addJob(job2);
        chain.addJob(job3);

        Assert.isFalse(chain.jobs.isEmpty());

        chain.removeJobsThatAreDisabledAndDependentFinalizers();
        
        Assert.isTrue(chain.jobs.isEmpty());
    }

    @IsTest
    private static void shouldRemoveSepcificDisabledJobsWithDependentFinalizers() {
        QueueableJobTest1 job1 = new QueueableJobTest1();
        QueueableJobTest2 job2 = new QueueableJobTest2();
        QueueableJobTest3 job3 = new QueueableJobTest3();
        QueueableJobTest4 job4 = new QueueableJobTest4();
        QueueableJobTest5 job5 = new QueueableJobTest5();
        QueueableJobTest6 job6 = new QueueableJobTest6();
        QueueableJobTest7 job7 = new QueueableJobTest7();
        QueueableJobTest8 job8 = new QueueableJobTest8();

        QueueableChain chain = new QueueableChain();
        chain.queueableJobSettingByJobName = new Map<String, QueueableJobSetting__mdt>{
            'QueueableJobTest1' => new QueueableJobSetting__mdt(
                DeveloperName = 'QueueableJobTest1',
                IsDisabled__c = true
            ),
            'QueueableJobTest7' => new QueueableJobSetting__mdt(
                DeveloperName = 'QueueableJobTest7',
                IsDisabled__c = false
            ),
            'QueueableJobTest8' => new QueueableJobSetting__mdt(
                DeveloperName = 'QueueableJobTest8',
                IsDisabled__c = true
            )
        };
        chain.addJob(job1);
        job2.parentCustomJobId = job1.customJobId;
        chain.addJob(job2);
        job3.parentCustomJobId = job1.customJobId;
        chain.addJob(job3);
        job4.parentCustomJobId = job3.customJobId;
        chain.addJob(job4);
        job5.parentCustomJobId = job4.customJobId;
        chain.addJob(job5);
        chain.addJob(job6);
        job7.parentCustomJobId = job6.customJobId;
        chain.addJob(job7);
        chain.addJob(job8);

        Assert.isFalse(chain.jobs.isEmpty());

        chain.removeJobsThatAreDisabledAndDependentFinalizers();
        
        Assert.areEqual(2, chain.jobs.size());
        Assert.areEqual(job6.uniqueName, chain.jobs[0].uniqueName);
        Assert.areEqual(job7.uniqueName, chain.jobs[1].uniqueName);
    }

    @IsTest
    private static void shouldCreateResultsForJob() {
        QueueableJobTest1 job1 = new QueueableJobTest1();
        QueueableJobTest2 job2 = new QueueableJobTest2();

        QueueableChain chain = new QueueableChain();
        chain.queueableJobSettingByJobName = new Map<String, QueueableJobSetting__mdt>{
            'QueueableJobTest1' => new QueueableJobSetting__mdt(
                DeveloperName = 'QueueableJobTest1',
                CreateResult__c = true
            )
        };
        QueueableManager.get().setChain(chain);

        Assert.isTrue([SELECT Id FROM AsyncResult__c].isEmpty());
        
        Test.startTest();
        Async.AsyncResult result1 = Async.queueable(job1)
            .enqueue();
        Async.AsyncResult result2 = Async.queueable(job2)
            .enqueue();
        Test.stopTest();

        AsyncResult__c job1Result = [SELECT Id, SalesforceJobId__c, CustomJobId__c, Result__c FROM AsyncResult__c WHERE CustomJobId__c = :result1.customJobId LIMIT 1];
        Assert.areEqual(result1.customJobId, job1Result.CustomJobId__c, 'Custom job ID should match the one from the result.');
        Assert.areEqual(
            1,
            [SELECT Id FROM AsyncApexJob WHERE Status = 'Completed' AND Id = :job1Result.SalesforceJobId__c].size(),
            'Should have one completed job for QueueableJobTest1.'
        );
        Assert.areEqual('SUCCESS', job1Result.Result__c, 'Result should be "Success" for the first job.');

        Assert.isTrue(
            [SELECT Id, SalesforceJobId__c, CustomJobId__c, Result__c FROM AsyncResult__c WHERE CustomJobId__c = :result2.customJobId LIMIT 1].isEmpty(),
            'Should not create result for QueueableJobTest2 as it does not have CreateResult__c set to true.'
        );
        Assert.areEqual(
            1,
            [SELECT Id FROM AsyncApexJob WHERE Status = 'Completed' AND Id = :result2.salesforceJobId].size(),
            'Should have one completed job for QueueableJobTest2.'
        );
    }

    @IsTest
    static void shouldScheduleEveryHourOn5Minute() {
        Test.startTest();
        Async.schedulable(new SchedulableTest())
            .name(TEST_SCHEDULABLE_JOB_NAME)
            .cronExpression('0 5 * * * ? *')
            .schedule();
        Test.stopTest();


        List<CronTrigger> triggers = [SELECT CronExpression, NextFireTime FROM CronTrigger WHERE CronJobDetail.Name = :TEST_SCHEDULABLE_JOB_NAME];
        Assert.areEqual(1, triggers.size(), 'Should have one trigger scheduled.');
        Assert.areEqual('0 5 * * * ? *', triggers[0].CronExpression, 'Cron expression should match the scheduled one.');
        Assert.isNotNull(triggers[0].NextFireTime, 'Next fire time should not be null.');
        Assert.isTrue(Math.mod(triggers[0].NextFireTime.minute(), 5) == 0, 'Next fire time should be every 5 minutes.');
    }

    @IsTest
    static void shouldScheduleEvery10Minutes() {
        Test.startTest();
        List<Async.AsyncResult> results = Async.schedulable(new SchedulableTest())
            .name(TEST_SCHEDULABLE_JOB_NAME)
            .cronExpression(
                new CronBuilder()
                    .buildForEveryXMinutes(10)
            )
            .schedule();
        Test.stopTest();

        String nameLike = TEST_SCHEDULABLE_JOB_NAME + '%';
        List<CronTrigger> triggers = [SELECT CronExpression, NextFireTime FROM CronTrigger WHERE CronJobDetail.Name LIKE :nameLike];
        Assert.areEqual(6, triggers.size(), 'Should have six triggers scheduled for every 10 minutes.');
        Assert.areEqual(0, triggers[0].NextFireTime.minute());
        Assert.areEqual(results[0].salesforceJobId, triggers[0].Id);
        Assert.areEqual(10, triggers[1].NextFireTime.minute());
        Assert.areEqual(results[1].salesforceJobId, triggers[1].Id);
        Assert.areEqual(20, triggers[2].NextFireTime.minute());
        Assert.areEqual(results[2].salesforceJobId, triggers[2].Id);
        Assert.areEqual(30, triggers[3].NextFireTime.minute());
        Assert.areEqual(results[3].salesforceJobId, triggers[3].Id);
        Assert.areEqual(40, triggers[4].NextFireTime.minute());
        Assert.areEqual(results[4].salesforceJobId, triggers[4].Id);
        Assert.areEqual(50, triggers[5].NextFireTime.minute());
        Assert.areEqual(results[5].salesforceJobId, triggers[5].Id);
    }

    @IsTest
    static void shouldScheduleBatchJobEvery30Minutes() {
        Test.startTest();
        List<Async.AsyncResult> results = Async.batchable(new AsyncTest())
            .asSchedulable()
            .name(TEST_SCHEDULABLE_JOB_NAME)
            .cronExpression(
                new CronBuilder()
                    .buildForEveryXMinutes(30)
            )
            .schedule();
        Test.stopTest();

        String nameLike = TEST_SCHEDULABLE_JOB_NAME + '%';
        List<CronTrigger> triggers = [SELECT CronExpression, NextFireTime FROM CronTrigger WHERE CronJobDetail.Name LIKE :nameLike];
        Assert.areEqual(2, triggers.size(), 'Should have six triggers scheduled for every 10 minutes.');
        Assert.areEqual(0, triggers[0].NextFireTime.minute());
        Assert.areEqual(results[0].salesforceJobId, triggers[0].Id);
        Assert.areEqual(30, triggers[1].NextFireTime.minute());
        Assert.areEqual(results[1].salesforceJobId, triggers[1].Id);
    }

    @IsTest
    static void shouldFailToScheduleEvery50Minutes() {
        Test.startTest();
        try {
            Async.schedulable(new SchedulableTest())
            .name(TEST_SCHEDULABLE_JOB_NAME)
            .cronExpression(
                new CronBuilder()
                    .buildForEveryXMinutes(50)
            )
            .schedule();
            Assert.fail('Should throw exception when trying to schedule every 50 minutes.');
        } catch (Exception ex) {
            Assert.areEqual('Every X minutes must be 30 or less.', ex.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void shouldScheduleEveryHour() {
        Test.startTest();
        Async.schedulable(new SchedulableTest())
            .name(TEST_SCHEDULABLE_JOB_NAME)
            .cronExpression(
                new CronBuilder()
                    .everyHour(10)
            )
            .schedule();
        Test.stopTest();

        String nameLike = TEST_SCHEDULABLE_JOB_NAME + '%';
        List<CronTrigger> triggers = [SELECT CronExpression, NextFireTime FROM CronTrigger WHERE CronJobDetail.Name LIKE :nameLike];
        Assert.areEqual(1, triggers.size());
        Assert.areEqual('0 10 * * * ? *', triggers[0].CronExpression);
        Assert.areEqual(10, triggers[0].NextFireTime.minute());
    }

    @IsTest
    static void shouldScheduleEvery5Hour() {
        Test.startTest();
        Async.schedulable(new SchedulableTest())
            .name(TEST_SCHEDULABLE_JOB_NAME)
            .cronExpression(
                new CronBuilder()
                    .everyXHours(5, 25)
            )
            .schedule();
        Test.stopTest();

        String nameLike = TEST_SCHEDULABLE_JOB_NAME + '%';
        List<CronTrigger> triggers = [SELECT CronExpression, NextFireTime FROM CronTrigger WHERE CronJobDetail.Name LIKE :nameLike];
        Assert.areEqual(1, triggers.size());
        Assert.areEqual('0 25 */5 * * ? *', triggers[0].CronExpression);
        Assert.areEqual(25, triggers[0].NextFireTime.minute());
        Assert.isTrue(Math.mod(triggers[0].NextFireTime.hour(), 5) == 0);
    }

    @IsTest
    static void shouldScheduleEveryDay() {
        Test.startTest();
        Async.schedulable(new SchedulableTest())
            .name(TEST_SCHEDULABLE_JOB_NAME)
            .cronExpression(
                new CronBuilder()
                    .everyDay(10, 30)
            )
            .schedule();
        Test.stopTest();

        String nameLike = TEST_SCHEDULABLE_JOB_NAME + '%';
        List<CronTrigger> triggers = [SELECT CronExpression, NextFireTime FROM CronTrigger WHERE CronJobDetail.Name LIKE :nameLike];
        Assert.areEqual(1, triggers.size());
        Assert.areEqual('0 30 10 * * ? *', triggers[0].CronExpression);
        Assert.areEqual(30, triggers[0].NextFireTime.minute());
        Assert.areEqual(10, triggers[0].NextFireTime.hour());
    }

    @IsTest
    static void shouldScheduleEvery3Days() {
        Test.startTest();
        Async.schedulable(new SchedulableTest())
            .name(TEST_SCHEDULABLE_JOB_NAME)
            .cronExpression(
                new CronBuilder()
                    .everyXDays(3, 5, 25)
            )
            .schedule();
        Test.stopTest();

        String nameLike = TEST_SCHEDULABLE_JOB_NAME + '%';
        List<CronTrigger> triggers = [SELECT CronExpression, NextFireTime FROM CronTrigger WHERE CronJobDetail.Name LIKE :nameLike];
        Assert.areEqual(1, triggers.size());
        Assert.areEqual('0 25 5 */3 * ? *', triggers[0].CronExpression);
        Assert.areEqual(25, triggers[0].NextFireTime.minute());
        Assert.areEqual(5, triggers[0].NextFireTime.hour());
    }

    @IsTest
    static void shouldScheduleEveryMonth() {
        Test.startTest();
        Async.schedulable(new SchedulableTest())
            .name(TEST_SCHEDULABLE_JOB_NAME)
            .cronExpression(
                new CronBuilder()
                    .everyMonth(3, 10, 30)
            )
            .schedule();
        Test.stopTest();

        String nameLike = TEST_SCHEDULABLE_JOB_NAME + '%';
        List<CronTrigger> triggers = [SELECT CronExpression, NextFireTime FROM CronTrigger WHERE CronJobDetail.Name LIKE :nameLike];
        Assert.areEqual(1, triggers.size());
        Assert.areEqual('0 30 10 3 * ? *', triggers[0].CronExpression);
        Assert.areEqual(30, triggers[0].NextFireTime.minute());
        Assert.areEqual(10, triggers[0].NextFireTime.hour());
        Assert.areEqual(3, triggers[0].NextFireTime.day());
    }

    @IsTest
    static void shouldScheduleEvery4Months() {
        Test.startTest();
        Async.schedulable(new SchedulableTest())
            .name(TEST_SCHEDULABLE_JOB_NAME)
            .cronExpression(
                new CronBuilder()
                    .everyXMonths(4, 3, 5, 25)
            )
            .schedule();
        Test.stopTest();

        String nameLike = TEST_SCHEDULABLE_JOB_NAME + '%';
        List<CronTrigger> triggers = [SELECT CronExpression, NextFireTime FROM CronTrigger WHERE CronJobDetail.Name LIKE :nameLike];
        Assert.areEqual(1, triggers.size());
        Assert.areEqual('0 25 5 3 */4 ? *', triggers[0].CronExpression);
        Assert.areEqual(25, triggers[0].NextFireTime.minute());
        Assert.areEqual(5, triggers[0].NextFireTime.hour());
        Assert.areEqual(3, triggers[0].NextFireTime.day());
    }

    @IsTest
    static void shouldFailOnMissingSchedulableJob() {
        Test.startTest();
        try {
            Async.schedulable(null)
                .schedule();
            Assert.fail('Should throw exception when trying to schedule a null schedulable job.');
        } catch (Exception ex) {
            Assert.areEqual(SchedulableManager.ERROR_MESSAGE_JOB_NOT_SET, ex.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void shouldFailOnMissingName() {
        Test.startTest();
        try {
            Async.schedulable(new SchedulableTest())
                .schedule();
            Assert.fail('Should throw exception when trying to schedule a schedulable job without a name.');
        } catch (Exception ex) {
            Assert.areEqual(SchedulableManager.ERROR_MESSAGE_JOB_NAME, ex.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void shouldFailOnMissingCronAndMinutesFromNow() {
        Test.startTest();
        try {
            Async.schedulable(new SchedulableTest())
                .name(TEST_SCHEDULABLE_JOB_NAME)
                .schedule();
            Assert.fail('Should throw exception when trying to schedule a schedulable job without cron expressions or minutes from now.');
        } catch (Exception ex) {
            Assert.areEqual(SchedulableManager.ERROR_MESSAGE_CRON_AND_MINUTES_NOT_SET, ex.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void shouldFailOnHavingBothCronAndMinutesFromNow() {
        Test.startTest();
        try {
            Async.batchable(new AsyncTest())
                .minutesFromNow(5)
                .asSchedulable()
                .name(TEST_SCHEDULABLE_JOB_NAME)
                .cronExpression(
                    new CronBuilder()
                        .everyXMonths(4, 3, 5, 25)
                )
                .schedule();
            Assert.fail('Should throw exception when trying to schedule a schedulable job with both cron expressions and minutes from now.');
        } catch (Exception ex) {
            Assert.areEqual(SchedulableManager.ERROR_MESSAGE_CRON_AND_MINUTES_SET, ex.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void shouldExecuteBatchJob() {
        Test.startTest();
        Async.AsyncResult result = Async.batchable(new AsyncTest())
            .scopeSize(100)
            .execute();
        Test.stopTest();

        Assert.areEqual(
            1,
            [SELECT Id FROM AsyncApexJob WHERE Id = :result.salesforceJobId AND ApexClass.Name = 'AsyncTest' AND Status = 'Completed'].size(),
            'Should have one batch job executed.'
        );
    }

    @IsTest
    static void shouldScheduleBatchJobIn5Minutes() {
        Test.startTest();
        Async.batchable(new AsyncTest())
            .scopeSize(100)
            .minutesFromNow(5)
            .asSchedulable()
            .name(TEST_SCHEDULABLE_JOB_NAME)
            .schedule();
        Test.stopTest();

        List<CronTrigger> triggers = [SELECT CronExpression, NextFireTime FROM CronTrigger WHERE CronJobDetail.Name = :TEST_SCHEDULABLE_JOB_NAME];
        Assert.areEqual(1, triggers.size(), 'Should have one trigger scheduled.');
        Assert.areEqual(DateTime.now().addMinutes(5).minute(), triggers[0].NextFireTime.minute(), 'Next fire time should be in 5 minutes.');
    }

    @IsTest
    static void shouldScheduleQueueableJobEveryDay() {
        Test.startTest();
        Async.queueable(new SuccessfulQueueableTest())
            .delay(1)
            .asSchedulable()
            .name(TEST_SCHEDULABLE_JOB_NAME)
            .cronExpression(
                new CronBuilder()
                    .everyDay(10, 30)
            )
            .schedule();
        Test.stopTest();

        String nameLike = TEST_SCHEDULABLE_JOB_NAME + '%';
        List<CronTrigger> triggers = [SELECT CronExpression, NextFireTime FROM CronTrigger WHERE CronJobDetail.Name LIKE :nameLike];
        Assert.areEqual(1, triggers.size());
        Assert.areEqual('0 30 10 * * ? *', triggers[0].CronExpression);
        Assert.areEqual(30, triggers[0].NextFireTime.minute());
        Assert.areEqual(10, triggers[0].NextFireTime.hour());
    }

    @IsTest
    static void shouldFailWhenSchedulingJobWithTheSameName() {
        Test.startTest();
        try {
            SchedulableBuilder builder = Async.batchable(new AsyncTest())
                .asSchedulable()
                .name(TEST_SCHEDULABLE_JOB_NAME)
                .cronExpression(
                    new CronBuilder()
                        .everyXMonths(4, 3, 5, 25)
                );
            builder.schedule();
            builder.schedule();
            Assert.fail('Should throw system exception when trying to schedule the job with the same name.');
        } catch (Exception ex) {
            Assert.areEqual('System.AsyncException', ex.getTypeName());
        }
        Test.stopTest();
    }

    @IsTest
    static void shouldSkipWhenSchedulingJobWithTheSameName() {
        Test.startTest();
        SchedulableBuilder builder = Async.queueable(new SuccessfulQueueableTest())
            .asSchedulable()
            .name(TEST_SCHEDULABLE_JOB_NAME)
            .cronExpression(
                new CronBuilder()
                    .everyDay(10, 30)
            )
            .skipWhenAlreadyScheduled();
        builder.schedule();
        builder.schedule();
        Test.stopTest();

        String nameLike = TEST_SCHEDULABLE_JOB_NAME + '%';
        List<CronTrigger> triggers = [SELECT CronExpression, NextFireTime FROM CronTrigger WHERE CronJobDetail.Name LIKE :nameLike];
        Assert.areEqual(1, triggers.size());
        Assert.areEqual('0 30 10 * * ? *', triggers[0].CronExpression);
        Assert.areEqual(30, triggers[0].NextFireTime.minute());
        Assert.areEqual(10, triggers[0].NextFireTime.hour());
    }

    public Iterable<Account> start(Database.BatchableContext bc){
        // This is just a placeholder to start the batch.
        return new List<Account>{ new Account() };
    }

    public void execute(Database.BatchableContext ctx, List<Account> scope){
    }

    public void finish(Database.BatchableContext bc){
    }

    private class SuccessfulQueueableTest extends QueueableJob {
        public override void work() {
            insert new Account(Name = Async.getQueueableJobContext()?.currentJob?.uniqueName);
        }
    }

    private class FailureQueueableTest extends QueueableJob.AllowsCallouts {
        public override void work() {
            insert new Account(Name = Async.getQueueableJobContext()?.currentJob?.uniqueName);
            throw new CustomException(AsyncTest.CUSTOM_ERROR_MESSAGE);
        }
    }

    private class QueueableTestFinalizer extends QueueableJob.Finalizer {
        public override void work() {
            FinalizerContext finalizerCtx = Async.getQueueableJobContext()?.finalizerCtx;
            insert new Account(Name = Async.getQueueableJobContext()?.currentJob?.uniqueName, 
                Description = finalizerCtx?.getResult() == ParentJobResult.SUCCESS ? 'Success' : finalizerCtx?.getException()?.getMessage());
        }
    }

    private class FinalizerErrorQueueableTest extends QueueableJob {
        public override void work() {
            Async.queueable(new SuccessfulQueueableTest())
                .attachFinalizer();
        }
    }

    private class QueueableJobTest1 extends QueueableJob {
        public override void work() {}
    }

    private class QueueableJobTest2 extends QueueableJob {
        public override void work() {}
    }

    private class QueueableJobTest3 extends QueueableJob {
        public override void work() {}
    }

    private class QueueableJobTest4 extends QueueableJob {
        public override void work() {}
    }

    private class QueueableJobTest5 extends QueueableJob {
        public override void work() {}
    }

    private class QueueableJobTest6 extends QueueableJob {
        public override void work() {}
    }

    private class QueueableJobTest7 extends QueueableJob {
        public override void work() {}
    }

    private class QueueableJobTest8 extends QueueableJob {
        public override void work() {}
    }

    private class SchedulableTest implements Schedulable {
        public void execute(SchedulableContext ctx) {
        }
    }

    private class CustomException extends Exception {
    }
}
