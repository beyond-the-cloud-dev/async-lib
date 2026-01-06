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
    private static final String PRIMITIVE_VALUE_INITIAL = 'INITIAL_VALUE';

    @IsTest
    private static void shouldEnqueue60QueueablesSuccessfully() {
        SuccessfulQueueableTest q = new SuccessfulQueueableTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Account]);
        Id initialQueuableChainSchedulableId;
        List<CronTrigger> cronTriggers;

        Test.startTest();
        for (Integer idx = 0; idx < 60; idx++) {
            Async.Result ar = Async.queueable(q).enqueue();
            if (idx <= Limits.getLimitQueueableJobs() - 1) {
                Assert.areEqual(
                    QueueableManager.EnqueueType.NEW_CHAIN,
                    ar.queueableChainState.enqueueType,
                    'Should not be enqueued via batch.'
                );
            } else {
                Assert.areEqual(
                    QueueableManager.EnqueueType.INITIAL_QUEUEABLE_CHAIN_SCHEDULABLE,
                    ar.queueableChainState.enqueueType,
                    'Should be enqueued via batch.'
                );
            }
        }
        initialQueuableChainSchedulableId = Async.getQueueableChainSchedulableId();
        cronTriggers = [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'QueueableChainSchedulable%'
        ];
        Test.stopTest();

        Assert.areEqual(
            50,
            [SELECT COUNT() FROM Account],
            'Should have 50 job runs (50 queueable and 1 scheduled batch that was not executed yet).'
        );
        Assert.areEqual(
            1,
            cronTriggers.size(),
            'Should schedule only one batchable job with the rest.'
        );
        Assert.areEqual(
            initialQueuableChainSchedulableId,
            cronTriggers[0].Id,
            'The one scheduled batch job should have the same Id as the one returned from Async.getQueueableChainSchedulableId()'
        );
        List<CronTrigger> currentCronTriggers = [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'QueueableChainSchedulable%'
        ];
        Assert.areEqual(
            0,
            currentCronTriggers.size(),
            'The scheduled job should be deleted once finished.'
        );
    }

    @IsTest
    private static void shouldEnqueue60QueueablesWithDelaySuccessfully() {
        SuccessfulQueueableTest q = new SuccessfulQueueableTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Account]);
        Id initialQueuableChainSchedulableId;
        List<CronTrigger> cronTriggers;

        Test.startTest();
        for (Integer idx = 0; idx < 60; idx++) {
            Async.queueable(q).delay(1).enqueue();
        }
        initialQueuableChainSchedulableId = Async.getQueueableChainSchedulableId();
        cronTriggers = [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'QueueableChainSchedulable%'
        ];
        Test.stopTest();

        Assert.areEqual(
            50,
            [SELECT COUNT() FROM Account],
            'Should have 50 job runs (50 queueable and 1 scheduled batch that was not executed yet).'
        );
        Assert.areEqual(
            1,
            cronTriggers.size(),
            'Should schedule only one batchable job with the rest.'
        );
        Assert.areEqual(
            initialQueuableChainSchedulableId,
            cronTriggers[0].Id,
            'The one scheduled batch job should have the same Id as the one returned from Async.getQueueableChainSchedulableId()'
        );
        List<CronTrigger> currentCronTriggers = [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'QueueableChainSchedulable%'
        ];
        Assert.areEqual(
            0,
            currentCronTriggers.size(),
            'The scheduled job should be deleted once finished.'
        );
    }

    @IsTest
    private static void shouldEnqueue60QueueablesSuccessfullyWithAllItemsFailedWithRollback() {
        FailureQueueableTest q = new FailureQueueableTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Account]);
        Id initialQueuableChainSchedulableId;
        List<CronTrigger> cronTriggers;

        Test.startTest();
        for (Integer idx = 0; idx < 60; idx++) {
            Async.queueable(q).continueOnJobExecuteFail().rollbackOnJobExecuteFail().enqueue();
        }
        initialQueuableChainSchedulableId = Async.getQueueableChainSchedulableId();
        cronTriggers = [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'QueueableChainSchedulable%'
        ];
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Account], 'Should have no Accounts created.');
        Assert.areEqual(
            1,
            cronTriggers.size(),
            'Should schedule only one batchable job with the rest.'
        );
        Assert.areEqual(
            initialQueuableChainSchedulableId,
            cronTriggers[0].Id,
            'The one scheduled batch job should have the same Id as the one returned from Async.getQueueableChainSchedulableId()'
        );
        List<CronTrigger> currentCronTriggers = [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'QueueableChainSchedulable%'
        ];
        Assert.areEqual(
            0,
            currentCronTriggers.size(),
            'The scheduled job should be deleted once finished.'
        );
    }

    @IsTest
    private static void shouldEnqueue60QueueablesSuccessfullyWithAllItemsFailedWithoutRollback() {
        FailureQueueableTest q = new FailureQueueableTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Account]);
        Id initialQueuableChainSchedulableId;
        List<CronTrigger> cronTriggers;

        Test.startTest();
        for (Integer idx = 0; idx < 60; idx++) {
            Async.queueable(q).continueOnJobExecuteFail().enqueue();
        }
        initialQueuableChainSchedulableId = Async.getQueueableChainSchedulableId();
        cronTriggers = [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'QueueableChainSchedulable%'
        ];
        Test.stopTest();

        Assert.areEqual(50, [SELECT COUNT() FROM Account], 'Inserted Accounts are not rollbacked.');
        Assert.areEqual(
            1,
            cronTriggers.size(),
            'Should schedule only one batchable job with the rest.'
        );
        Assert.areEqual(
            initialQueuableChainSchedulableId,
            cronTriggers[0].Id,
            'The one scheduled batch job should have the same Id as the one returned from Async.getQueueableChainSchedulableId()'
        );
        List<CronTrigger> currentCronTriggers = [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'QueueableChainSchedulable%'
        ];
        Assert.areEqual(
            0,
            currentCronTriggers.size(),
            'The scheduled job should be deleted once finished.'
        );
    }

    @IsTest
    private static void shouldOnlyEnqueueOneJobDueToAsyncOptions() {
        SuccessfulQueueableTest q = new SuccessfulQueueableTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Account]);
        AsyncOptions options = new AsyncOptions();
        options.DuplicateSignature = QueueableDuplicateSignature.Builder()
            .addString(TEST_SIGNATURE_NAME)
            .build();

        Test.startTest();
        for (Integer idx = 0; idx < 50; idx++) {
            Async.queueable(q).asyncOptions(options).continueOnJobEnqueueFail().enqueue();
        }
        Test.stopTest();

        Assert.areEqual(1, [SELECT COUNT() FROM Account], 'Only one job should run.');
    }

    @IsTest
    private static void shouldFailJobOnDuplicateAsyncOptionsSignature() {
        SuccessfulQueueableTest q = new SuccessfulQueueableTest();

        AsyncOptions options = new AsyncOptions();
        options.DuplicateSignature = QueueableDuplicateSignature.Builder()
            .addString(TEST_SIGNATURE_NAME)
            .build();

        Test.startTest();
        try {
            Async.queueable(q).asyncOptions(options).enqueue();
            Async.queueable(q).asyncOptions(options).enqueue();
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
            Async.queueable(failureJob).enqueue();
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
            Async.queueable(finalizer).attachFinalizer();
            Test.stopTest();
            Assert.fail(
                'Should throw exception when trying to attach finalizer in non-chain context.'
            );
        } catch (Exception ex) {
            Assert.areEqual(
                QueueableManager.ERROR_MESSAGE_CANNOT_ATTACH_FINALIZER,
                ex.getMessage()
            );
        }
    }

    @IsTest
    private static void shouldFailToEnqueueFinalizerDirectlyByEnqueueMethod() {
        QueueableTestFinalizer finalizer = new QueueableTestFinalizer();

        try {
            Test.startTest();
            Async.queueable(finalizer).enqueue();
            Test.stopTest();
            Assert.fail('Should throw exception when trying to enqueue finalizer directly.');
        } catch (Exception ex) {
            Assert.areEqual(
                QueueableManager.ERROR_MESSAGE_CANNOT_ENQUEUE_FINALIZER_DIRECTLY,
                ex.getMessage()
            );
        }
    }

    @IsTest
    private static void shouldFailToAttachFinalizerWhenQueueableJobIsNotFinalizer() {
        FinalizerErrorQueueableTest q = new FinalizerErrorQueueableTest();

        try {
            Test.startTest();
            Async.queueable(q).enqueue();
            Test.stopTest();
            Assert.fail(
                'Should throw exception when trying to attach finalizer to a non-finalizer job.'
            );
        } catch (Exception ex) {
            Assert.areEqual(
                QueueableManager.ERROR_MESSAGE_FINALIZER_JOB_MUST_EXTEND_FINALIZER,
                ex.getMessage()
            );
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
            'AsyncTest.QueueableJobTest1' => new QueueableJobSetting__mdt(
                DeveloperName = 'AsyncTest.QueueableJobTest1',
                IsDisabled__c = true
            ),
            'AsyncTest.QueueableJobTest7' => new QueueableJobSetting__mdt(
                DeveloperName = 'AsyncTest.QueueableJobTest7',
                IsDisabled__c = false
            ),
            'AsyncTest.QueueableJobTest8' => new QueueableJobSetting__mdt(
                DeveloperName = 'AsyncTest.QueueableJobTest8',
                IsDisabled__c = true
            )
        };
        chain.addJob(job1);
        chain.addJob(job2);
        chain.addJob(job3);
        chain.addJob(job4);
        chain.addJob(job5);
        chain.addJob(job6);
        chain.addJob(job7);
        chain.addJob(job8);

        // Setting finalizers after sorting, since in normal execution finalizer can be only added in the queueable chain context
        job2.parentCustomJobId = job1.customJobId;
        job3.parentCustomJobId = job1.customJobId;
        job4.parentCustomJobId = job3.customJobId;
        job5.parentCustomJobId = job4.customJobId;
        job7.parentCustomJobId = job6.customJobId;

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

        QueueableChain chain1 = new QueueableChain();
        chain1.queueableJobSettingByJobName = new Map<String, QueueableJobSetting__mdt>{
            'AsyncTest.QueueableJobTest1' => new QueueableJobSetting__mdt(
                DeveloperName = 'AsyncTest.QueueableJobTest1',
                CreateResult__c = true
            )
        };
        QueueableChain chain2 = new QueueableChain();
        chain2.queueableJobSettingByJobName = new Map<String, QueueableJobSetting__mdt>{
            'AsyncTest.QueueableJobTest1' => new QueueableJobSetting__mdt(
                DeveloperName = 'AsyncTest.QueueableJobTest1',
                CreateResult__c = true
            )
        };

        Assert.isTrue([SELECT Id FROM AsyncResult__c].isEmpty());

        Test.startTest();
        QueueableManager.get().setChain(chain1);
        Async.Result result1 = Async.queueable(job1).enqueue();

        QueueableManager.get().setChain(chain2);
        Async.Result result2 = Async.queueable(job2).enqueue();
        Test.stopTest();

        AsyncResult__c job1Result = [
            SELECT Id, SalesforceJobId__c, CustomJobId__c, Result__c
            FROM AsyncResult__c
            WHERE CustomJobId__c = :result1.customJobId
            LIMIT 1
        ];
        Assert.areEqual(
            result1.customJobId,
            job1Result.CustomJobId__c,
            'Custom job ID should match the one from the result.'
        );
        Assert.areEqual(
            1,
            [
                    SELECT Id
                    FROM AsyncApexJob
                    WHERE Status = 'Completed' AND Id = :job1Result.SalesforceJobId__c
                ]
                .size(),
            'Should have one completed job for QueueableJobTest1.'
        );
        Assert.areEqual(
            'SUCCESS',
            job1Result.Result__c,
            'Result should be "Success" for the first job.'
        );

        Assert.isTrue(
            [
                    SELECT Id, SalesforceJobId__c, CustomJobId__c, Result__c
                    FROM AsyncResult__c
                    WHERE CustomJobId__c = :result2.customJobId
                    LIMIT 1
                ]
                .isEmpty(),
            'Should not create result for QueueableJobTest2 as it does not have CreateResult__c set to true.'
        );
        Assert.areEqual(
            1,
            [
                    SELECT Id
                    FROM AsyncApexJob
                    WHERE Status = 'Completed' AND Id = :result2.salesforceJobId
                ]
                .size(),
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

        List<CronTrigger> triggers = [
            SELECT CronExpression, NextFireTime
            FROM CronTrigger
            WHERE CronJobDetail.Name = :TEST_SCHEDULABLE_JOB_NAME
        ];
        Assert.areEqual(1, triggers.size(), 'Should have one trigger scheduled.');
        Assert.areEqual(
            '0 5 * * * ? *',
            triggers[0].CronExpression,
            'Cron expression should match the scheduled one.'
        );
        Assert.isNotNull(triggers[0].NextFireTime, 'Next fire time should not be null.');
        Assert.isTrue(
            Math.mod(triggers[0].NextFireTime.minute(), 5) == 0,
            'Next fire time should be every 5 minutes.'
        );
    }

    @IsTest
    static void shouldScheduleEvery10Minutes() {
        Test.startTest();
        List<Async.Result> results = Async.schedulable(new SchedulableTest())
            .name(TEST_SCHEDULABLE_JOB_NAME)
            .cronExpression(new CronBuilder().buildForEveryXMinutes(10))
            .schedule();
        Test.stopTest();

        String nameLike = TEST_SCHEDULABLE_JOB_NAME + '%';
        List<CronTrigger> triggers = [
            SELECT CronExpression, NextFireTime
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE :nameLike
        ];
        Assert.areEqual(
            6,
            triggers.size(),
            'Should have six triggers scheduled for every 10 minutes.'
        );
        Assert.areEqual(0, triggers[0].NextFireTime.minute());
        Assert.areEqual(results[0].salesforceJobId, triggers[0].Id);
        Assert.areEqual(results[0].asyncType, Async.AsyncType.SCHEDULABLE);
        Assert.areEqual(10, triggers[1].NextFireTime.minute());
        Assert.areEqual(results[1].salesforceJobId, triggers[1].Id);
        Assert.areEqual(results[1].asyncType, Async.AsyncType.SCHEDULABLE);
        Assert.areEqual(20, triggers[2].NextFireTime.minute());
        Assert.areEqual(results[2].salesforceJobId, triggers[2].Id);
        Assert.areEqual(results[2].asyncType, Async.AsyncType.SCHEDULABLE);
        Assert.areEqual(30, triggers[3].NextFireTime.minute());
        Assert.areEqual(results[3].salesforceJobId, triggers[3].Id);
        Assert.areEqual(results[3].asyncType, Async.AsyncType.SCHEDULABLE);
        Assert.areEqual(40, triggers[4].NextFireTime.minute());
        Assert.areEqual(results[4].salesforceJobId, triggers[4].Id);
        Assert.areEqual(results[4].asyncType, Async.AsyncType.SCHEDULABLE);
        Assert.areEqual(50, triggers[5].NextFireTime.minute());
        Assert.areEqual(results[5].salesforceJobId, triggers[5].Id);
        Assert.areEqual(results[5].asyncType, Async.AsyncType.SCHEDULABLE);
    }

    @IsTest
    static void shouldScheduleBatchJobEvery30Minutes() {
        Test.startTest();
        List<Async.Result> results = Async.batchable(new AsyncTest())
            .asSchedulable()
            .name(TEST_SCHEDULABLE_JOB_NAME)
            .cronExpression(new CronBuilder().buildForEveryXMinutes(30))
            .schedule();
        Test.stopTest();

        String nameLike = TEST_SCHEDULABLE_JOB_NAME + '%';
        List<CronTrigger> triggers = [
            SELECT CronExpression, NextFireTime
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE :nameLike
        ];
        Assert.areEqual(
            2,
            triggers.size(),
            'Should have six triggers scheduled for every 10 minutes.'
        );
        Assert.areEqual(0, triggers[0].NextFireTime.minute());
        Assert.areEqual(results[0].salesforceJobId, triggers[0].Id);
        Assert.areEqual(results[0].asyncType, Async.AsyncType.SCHEDULABLE);
        Assert.areEqual(30, triggers[1].NextFireTime.minute());
        Assert.areEqual(results[1].salesforceJobId, triggers[1].Id);
        Assert.areEqual(results[1].asyncType, Async.AsyncType.SCHEDULABLE);
    }

    @IsTest
    static void shouldFailToScheduleEvery50Minutes() {
        Test.startTest();
        try {
            Async.schedulable(new SchedulableTest())
                .name(TEST_SCHEDULABLE_JOB_NAME)
                .cronExpression(new CronBuilder().buildForEveryXMinutes(50))
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
            .cronExpression(new CronBuilder().everyHour(10))
            .schedule();
        Test.stopTest();

        String nameLike = TEST_SCHEDULABLE_JOB_NAME + '%';
        List<CronTrigger> triggers = [
            SELECT CronExpression, NextFireTime
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE :nameLike
        ];
        Assert.areEqual(1, triggers.size());
        Assert.areEqual('0 10 * * * ? *', triggers[0].CronExpression);
        Assert.areEqual(10, triggers[0].NextFireTime.minute());
    }

    @IsTest
    static void shouldScheduleEvery5Hour() {
        Test.startTest();
        Async.schedulable(new SchedulableTest())
            .name(TEST_SCHEDULABLE_JOB_NAME)
            .cronExpression(new CronBuilder().everyXHours(5, 25))
            .schedule();
        Test.stopTest();

        String nameLike = TEST_SCHEDULABLE_JOB_NAME + '%';
        List<CronTrigger> triggers = [
            SELECT CronExpression, NextFireTime
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE :nameLike
        ];
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
            .cronExpression(new CronBuilder().everyDay(10, 30))
            .schedule();
        Test.stopTest();

        String nameLike = TEST_SCHEDULABLE_JOB_NAME + '%';
        List<CronTrigger> triggers = [
            SELECT CronExpression, NextFireTime
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE :nameLike
        ];
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
            .cronExpression(new CronBuilder().everyXDays(3, 5, 25))
            .schedule();
        Test.stopTest();

        String nameLike = TEST_SCHEDULABLE_JOB_NAME + '%';
        List<CronTrigger> triggers = [
            SELECT CronExpression, NextFireTime
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE :nameLike
        ];
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
            .cronExpression(new CronBuilder().everyMonth(3, 10, 30))
            .schedule();
        Test.stopTest();

        String nameLike = TEST_SCHEDULABLE_JOB_NAME + '%';
        List<CronTrigger> triggers = [
            SELECT CronExpression, NextFireTime
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE :nameLike
        ];
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
            .cronExpression(new CronBuilder().everyXMonths(4, 3, 5, 25))
            .schedule();
        Test.stopTest();

        String nameLike = TEST_SCHEDULABLE_JOB_NAME + '%';
        List<CronTrigger> triggers = [
            SELECT CronExpression, NextFireTime
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE :nameLike
        ];
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
            Async.schedulable(null).schedule();
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
            Async.schedulable(new SchedulableTest()).schedule();
            Assert.fail(
                'Should throw exception when trying to schedule a schedulable job without a name.'
            );
        } catch (Exception ex) {
            Assert.areEqual(SchedulableManager.ERROR_MESSAGE_JOB_NAME, ex.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void shouldFailOnMissingCronAndMinutesFromNow() {
        Test.startTest();
        try {
            Async.schedulable(new SchedulableTest()).name(TEST_SCHEDULABLE_JOB_NAME).schedule();
            Assert.fail(
                'Should throw exception when trying to schedule a schedulable job without cron expressions or minutes from now.'
            );
        } catch (Exception ex) {
            Assert.areEqual(
                SchedulableManager.ERROR_MESSAGE_CRON_AND_MINUTES_NOT_SET,
                ex.getMessage()
            );
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
                .cronExpression(new CronBuilder().everyXMonths(4, 3, 5, 25))
                .schedule();
            Assert.fail(
                'Should throw exception when trying to schedule a schedulable job with both cron expressions and minutes from now.'
            );
        } catch (Exception ex) {
            Assert.areEqual(SchedulableManager.ERROR_MESSAGE_CRON_AND_MINUTES_SET, ex.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void shouldExecuteBatchJob() {
        Test.startTest();
        Async.Result result = Async.batchable(new AsyncTest()).scopeSize(100).execute();
        Test.stopTest();

        Assert.areEqual(
            1,
            [
                    SELECT Id
                    FROM AsyncApexJob
                    WHERE
                        Id = :result.salesforceJobId
                        AND ApexClass.Name = 'AsyncTest'
                        AND Status = 'Completed'
                ]
                .size(),
            'Should have one batch job executed.'
        );
        Assert.areEqual(result.asyncType, Async.AsyncType.BATCHABLE);
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

        List<CronTrigger> triggers = [
            SELECT CronExpression, NextFireTime, CreatedDate
            FROM CronTrigger
            WHERE CronJobDetail.Name = :TEST_SCHEDULABLE_JOB_NAME
        ];
        Assert.areEqual(1, triggers.size(), 'Should have one trigger scheduled.');
        Assert.areEqual(
            triggers[0].CreatedDate.addMinutes(5).minute(),
            triggers[0].NextFireTime.minute(),
            'Next fire time should be in 5 minutes.'
        );
    }

    @IsTest
    static void shouldScheduleQueueableJobEveryDay() {
        Test.startTest();
        Async.queueable(new SuccessfulQueueableTest())
            .delay(1)
            .asSchedulable()
            .name(TEST_SCHEDULABLE_JOB_NAME)
            .cronExpression(new CronBuilder().everyDay(10, 30))
            .schedule();
        Test.stopTest();

        String nameLike = TEST_SCHEDULABLE_JOB_NAME + '%';
        List<CronTrigger> triggers = [
            SELECT CronExpression, NextFireTime
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE :nameLike
        ];
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
                .cronExpression(new CronBuilder().everyXMonths(4, 3, 5, 25));
            builder.schedule();
            builder.schedule();
            Assert.fail(
                'Should throw system exception when trying to schedule the job with the same name.'
            );
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
            .cronExpression(new CronBuilder().everyDay(10, 30))
            .skipWhenAlreadyScheduled();
        builder.schedule();
        builder.schedule();
        Test.stopTest();

        String nameLike = TEST_SCHEDULABLE_JOB_NAME + '%';
        List<CronTrigger> triggers = [
            SELECT CronExpression, NextFireTime
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE :nameLike
        ];
        Assert.areEqual(1, triggers.size());
        Assert.areEqual('0 30 10 * * ? *', triggers[0].CronExpression);
        Assert.areEqual(30, triggers[0].NextFireTime.minute());
        Assert.areEqual(10, triggers[0].NextFireTime.hour());
    }

    @IsTest
    static void shouldSoftCloneTheJob() {
        String changedPrimitiveValue = 'changedPrimitiveValue';

        QueueableJobTest1 job1 = new QueueableJobTest1();
        Async.Result result1 = Async.queueable(job1).chain();

        // Complex member is passed by reference, what change the first job value
        job1.complexMember.primitiveMember = changedPrimitiveValue;
        Async.Result result2 = Async.queueable(job1).enqueue();

        QueueableJobTest1 firstEnqueuedJob = (QueueableJobTest1) result1.job;
        QueueableJobTest1 secondEnqueuedJob = (QueueableJobTest1) result2.job;

        Assert.areEqual(changedPrimitiveValue, firstEnqueuedJob.complexMember.primitiveMember);
        Assert.areEqual(changedPrimitiveValue, secondEnqueuedJob.complexMember.primitiveMember);
    }

    @IsTest
    static void shouldDeepCloneTheJob() {
        String changedPrimitiveValue = 'changedPrimitiveValue';

        QueueableJobTest1 job1 = new QueueableJobTest1();
        Async.Result result1 = Async.queueable(job1).deepClone().chain();

        // Due to above deep clone, all values above were passed by value
        job1.complexMember.primitiveMember = changedPrimitiveValue;
        Async.Result result2 = Async.queueable(job1).enqueue();

        QueueableJobTest1 firstEnqueuedJob = (QueueableJobTest1) result1.job;
        QueueableJobTest1 secondEnqueuedJob = (QueueableJobTest1) result2.job;

        Assert.areEqual(PRIMITIVE_VALUE_INITIAL, firstEnqueuedJob.complexMember.primitiveMember);
        Assert.areEqual(changedPrimitiveValue, secondEnqueuedJob.complexMember.primitiveMember);
    }

    @IsTest
    static void shouldExecuteChainedQueueableJob20Times() {
        Integer noOfChainedJobs = 20;
        Assert.areEqual(0, [SELECT COUNT() FROM Account]);

        Test.startTest();
        Async.queueable(new ChainedQueueableJob(noOfChainedJobs)).enqueue();
        Test.stopTest();

        Assert.areEqual(noOfChainedJobs, [SELECT COUNT() FROM Account]);
        Assert.areEqual(
            noOfChainedJobs,
            [
                SELECT COUNT()
                FROM AsyncApexJob
                WHERE
                    Status = 'Completed'
                    AND JobType = 'Queueable'
                    AND ApexClass.Name = 'AsyncTest'
            ]
        );
    }

    @IsTest
    static void shouldFailToSetAsyncOptionsAfterDelay() {
        SuccessfulQueueableTest q = new SuccessfulQueueableTest();

        try {
            Async.queueable(q).delay(1).asyncOptions(new AsyncOptions());
            Assert.fail('Should throw exception when setting asyncOptions after delay.');
        } catch (Exception ex) {
            Assert.areEqual(
                QueueableManager.ERROR_MESSAGE_ASYNC_OPTIONS_AFTER_DELAY,
                ex.getMessage()
            );
        }
    }

    @IsTest
    static void shouldFailToSetDelayAfterAsyncOptions() {
        SuccessfulQueueableTest q = new SuccessfulQueueableTest();

        try {
            Async.queueable(q).asyncOptions(new AsyncOptions()).delay(1);
            Assert.fail('Should throw exception when setting delay after asyncOptions.');
        } catch (Exception ex) {
            Assert.areEqual(
                QueueableManager.ERROR_MESSAGE_DELAY_AFTER_ASYNC_OPTIONS,
                ex.getMessage()
            );
        }
    }

    @IsTest
    static void shouldSetPriorityOnJob() {
        QueueableJobTest1 job = new QueueableJobTest1();

        Async.Result result = Async.queueable(job).priority(10).chain();

        Assert.areEqual(10, result.job.priority);
    }

    @IsTest
    static void shouldFailWhenBatchScopeSizeIsZeroOrLess() {
        try {
            Async.batchable(new AsyncTest()).scopeSize(0).execute();
            Assert.fail('Should throw exception when scope size is zero.');
        } catch (Exception ex) {
            Assert.areEqual('Scope size must be greater than zero.', ex.getMessage());
        }

        try {
            Async.batchable(new AsyncTest()).scopeSize(-1).execute();
            Assert.fail('Should throw exception when scope size is negative.');
        } catch (Exception ex) {
            Assert.areEqual('Scope size must be greater than zero.', ex.getMessage());
        }
    }

    @IsTest
    static void shouldFailWhenBatchMinutesFromNowIsZeroOrLess() {
        try {
            Async.batchable(new AsyncTest())
                .minutesFromNow(0)
                .asSchedulable()
                .name(TEST_SCHEDULABLE_JOB_NAME)
                .schedule();
            Assert.fail('Should throw exception when minutes from now is zero.');
        } catch (Exception ex) {
            Assert.areEqual('Minutes from now must be greater than zero.', ex.getMessage());
        }

        try {
            Async.batchable(new AsyncTest())
                .minutesFromNow(-5)
                .asSchedulable()
                .name(TEST_SCHEDULABLE_JOB_NAME)
                .schedule();
            Assert.fail('Should throw exception when minutes from now is negative.');
        } catch (Exception ex) {
            Assert.areEqual('Minutes from now must be greater than zero.', ex.getMessage());
        }
    }

    @IsTest
    static void shouldFailWhenBatchJobIsNull() {
        try {
            BatchableManager.get().execute(null);
            Assert.fail('Should throw exception when builder is null.');
        } catch (Exception ex) {
            Assert.areEqual('Batch job must be set.', ex.getMessage());
        }

        try {
            BatchableBuilder builder = new BatchableBuilder(new AsyncTest());
            builder.job = null;
            BatchableManager.get().execute(builder);
            Assert.fail('Should throw exception when job is null.');
        } catch (Exception ex) {
            Assert.areEqual('Batch job must be set.', ex.getMessage());
        }
    }

    @IsTest
    static void shouldExecuteBatchWithDefaultScopeSize() {
        Test.startTest();
        Async.Result result = Async.batchable(new AsyncTest()).execute();
        Test.stopTest();

        Assert.isNotNull(result.salesforceJobId);
        Assert.areEqual(Async.AsyncType.BATCHABLE, result.asyncType);
    }

    @IsTest
    static void shouldFailWhenCronExpressionIsBlank() {
        try {
            new CronBuilder('');
            Assert.fail('Should throw exception when cron expression is blank.');
        } catch (Exception ex) {
            Assert.areEqual('Cron expression cannot be blank.', ex.getMessage());
        }

        try {
            new CronBuilder('   ');
            Assert.fail('Should throw exception when cron expression is whitespace.');
        } catch (Exception ex) {
            Assert.areEqual('Cron expression cannot be blank.', ex.getMessage());
        }
    }

    @IsTest
    static void shouldFailWhenCronExpressionHasInvalidParts() {
        try {
            new CronBuilder('0 0 * *');
            Assert.fail('Should throw exception when cron has less than 6 parts.');
        } catch (Exception ex) {
            Assert.isTrue(ex.getMessage().contains('must have 6 or 7 parts'));
        }

        try {
            new CronBuilder('0 0 * * * ? * 2024 extra');
            Assert.fail('Should throw exception when cron has more than 7 parts.');
        } catch (Exception ex) {
            Assert.isTrue(ex.getMessage().contains('must have 6 or 7 parts'));
        }
    }

    @IsTest
    static void shouldParseCronExpressionWith7Parts() {
        CronBuilder cron = new CronBuilder('0 30 10 * * ? 2025');

        Assert.areEqual('0', cron.second);
        Assert.areEqual('30', cron.minute);
        Assert.areEqual('10', cron.hour);
        Assert.areEqual('*', cron.dayOfMonth);
        Assert.areEqual('*', cron.month);
        Assert.areEqual('?', cron.dayOfWeek);
        Assert.areEqual('2025', cron.optionalYear);
    }

    @IsTest
    static void shouldBuildCronExpressionWithSetters() {
        CronBuilder cron = new CronBuilder()
            .second('30')
            .minute('15')
            .hour('8')
            .dayOfMonth('1')
            .month('6')
            .dayOfWeek('MON')
            .optionalYear('2025');

        String expression = cron.getCronExpression();
        Assert.areEqual('30 15 8 1 6 MON 2025', expression);
    }

    @IsTest
    static void shouldBuildCronExpressionWithDefaults() {
        CronBuilder cron = new CronBuilder();
        String expression = cron.getCronExpression();

        Assert.areEqual('0 0 * * * ? *', expression);
    }

    @IsTest
    static void shouldFailWhenEveryXMinutesIsZeroOrNegative() {
        try {
            new CronBuilder().buildForEveryXMinutes(0);
            Assert.fail('Should throw exception when everyXMinutes is zero.');
        } catch (Exception ex) {
            Assert.areEqual('Every X minutes must be greater than zero.', ex.getMessage());
        }

        try {
            new CronBuilder().buildForEveryXMinutes(-1);
            Assert.fail('Should throw exception when everyXMinutes is negative.');
        } catch (Exception ex) {
            Assert.areEqual('Every X minutes must be greater than zero.', ex.getMessage());
        }
    }

    @IsTest
    static void shouldFailWhenEveryXHoursIsInvalid() {
        try {
            new CronBuilder().everyXHours(0, 30);
            Assert.fail('Should throw exception when everyXHours is zero.');
        } catch (Exception ex) {
            Assert.areEqual('Every X hours must be greater than zero.', ex.getMessage());
        }

        try {
            new CronBuilder().everyXHours(13, 30);
            Assert.fail('Should throw exception when everyXHours is greater than 12.');
        } catch (Exception ex) {
            Assert.areEqual('Every X hours must be 12 or less.', ex.getMessage());
        }
    }

    @IsTest
    static void shouldFailWhenEveryXDaysIsInvalid() {
        try {
            new CronBuilder().everyXDays(0, 10, 30);
            Assert.fail('Should throw exception when everyXDays is zero.');
        } catch (Exception ex) {
            Assert.areEqual('Every X days must be greater than zero.', ex.getMessage());
        }

        try {
            new CronBuilder().everyXDays(16, 10, 30);
            Assert.fail('Should throw exception when everyXDays is greater than 15.');
        } catch (Exception ex) {
            Assert.areEqual('Every X days must be 15 or less.', ex.getMessage());
        }
    }

    @IsTest
    static void shouldFailWhenEveryXMonthsIsInvalid() {
        try {
            new CronBuilder().everyXMonths(0, 1, 10, 30);
            Assert.fail('Should throw exception when everyXMonths is zero.');
        } catch (Exception ex) {
            Assert.areEqual('Every X months must be greater than zero.', ex.getMessage());
        }

        try {
            new CronBuilder().everyXMonths(7, 1, 10, 30);
            Assert.fail('Should throw exception when everyXMonths is greater than 6.');
        } catch (Exception ex) {
            Assert.areEqual('Every X months must be 6 or less.', ex.getMessage());
        }
    }

    @IsTest
    static void shouldBuildEveryHourCron() {
        CronBuilder cron = new CronBuilder().everyHour(45);

        Assert.areEqual('45', cron.minute);
        String expression = cron.getCronExpression();
        Assert.isTrue(expression.contains('45'));
    }

    @IsTest
    static void shouldBuildEveryDayCron() {
        CronBuilder cron = new CronBuilder().everyDay(14, 30);

        Assert.areEqual('14', cron.hour);
        Assert.areEqual('30', cron.minute);
    }

    @IsTest
    static void shouldBuildEveryMonthCron() {
        CronBuilder cron = new CronBuilder().everyMonth(15, 9, 0);

        Assert.areEqual('15', cron.dayOfMonth);
        Assert.areEqual('9', cron.hour);
        Assert.areEqual('0', cron.minute);
    }

    @IsTest
    static void shouldFailWhenQueueableChainFinalizerChainIsNull() {
        try {
            new QueueableChainFinalizer(null);
            Assert.fail('Should throw exception when chain is null.');
        } catch (Exception ex) {
            Assert.areEqual('QueueableChain cannot be null', ex.getMessage());
        }
    }

    @IsTest
    static void shouldFailWhenQueueableChainSchedulableChainIsNull() {
        try {
            new QueueableChainSchedulable(null);
            Assert.fail('Should throw exception when chain is null.');
        } catch (Exception ex) {
            Assert.areEqual('QueueableChain cannot be null', ex.getMessage());
        }
    }

    @IsTest
    static void shouldGetCurrentQueueableChainState() {
        SuccessfulQueueableTest q = new SuccessfulQueueableTest();

        Async.queueable(q).chain();
        Async.QueueableChainState state = Async.getCurrentQueueableChainState();

        Assert.isNotNull(state);
        Assert.isNotNull(state.jobs);
        Assert.areEqual(1, state.jobs.size());
    }

    @IsTest
    static void shouldGetQueueableJobContext() {
        Async.QueueableJobContext ctx = Async.getQueueableJobContext();

        Assert.isNotNull(ctx);
        Assert.isNull(ctx.currentJob);
    }

    @IsTest
    @SuppressWarnings('PMD.ApexUnitTestClassShouldHaveAsserts')
    static void shouldRemoveSchedulableJobWhenIdIsNull() {
        QueueableChainSchedulable.removeInitialQueuableChainSchedulableIfExists(null);
    }

    @IsTest
    @SuppressWarnings('PMD.ApexUnitTestClassShouldHaveAsserts,PMD.AvoidHardcodingId')
    static void shouldHandleRemoveSchedulableJobWithInvalidId() {
        QueueableChainSchedulable.removeInitialQueuableChainSchedulableIfExists(
            '001000000000000AAA'
        );
    }

    @IsTest
    static void shouldChainMultipleJobsWithBuilder() {
        QueueableJobTest1 job1 = new QueueableJobTest1();
        QueueableJobTest2 job2 = new QueueableJobTest2();

        Async.queueable(job1).chain(job2).chain();

        Async.QueueableChainState state = Async.getCurrentQueueableChainState();
        Assert.areEqual(2, state.jobs.size());
    }

    @IsTest
    static void shouldConvertQueueableToSchedulable() {
        SuccessfulQueueableTest q = new SuccessfulQueueableTest();

        Test.startTest();
        Async.queueable(q)
            .asSchedulable()
            .name(TEST_SCHEDULABLE_JOB_NAME)
            .cronExpression(new CronBuilder().everyDay(10, 30))
            .schedule();
        Test.stopTest();

        List<CronTrigger> triggers = [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name = :TEST_SCHEDULABLE_JOB_NAME
        ];
        Assert.areEqual(1, triggers.size());
    }

    @IsTest
    static void shouldHandleQueueableChainStateWithNullJobs() {
        Async.QueueableChainState state = new Async.QueueableChainState();

        state.setNextSalesforceJobIdFromFirstJob();
        Assert.isNull(state.nextSalesforceJobId);

        state.setNextCustomJobIdFromFirstJob();
        Assert.isNull(state.nextCustomJobId);
    }

    @IsTest
    static void shouldHandleQueueableChainStateWithEmptyJobs() {
        Async.QueueableChainState state = new Async.QueueableChainState();
        state.setJobs(new List<QueueableJob>());

        state.setNextSalesforceJobIdFromFirstJob();
        Assert.isNull(state.nextSalesforceJobId);

        state.setNextCustomJobIdFromFirstJob();
        Assert.isNull(state.nextCustomJobId);
    }

    @IsTest
    static void shouldSetEnqueueTypeOnChainState() {
        Async.QueueableChainState state = new Async.QueueableChainState();

        state.setEnqueueType(QueueableManager.EnqueueType.NEW_CHAIN);
        Assert.areEqual(QueueableManager.EnqueueType.NEW_CHAIN, state.enqueueType);

        state.setEnqueueType(QueueableManager.EnqueueType.EXISTING_CHAIN);
        Assert.areEqual(QueueableManager.EnqueueType.EXISTING_CHAIN, state.enqueueType);
    }

    @IsTest
    static void shouldCompareJobsWithBothFinalizersAndSamePriority() {
        QueueableJobTest1 job1 = new QueueableJobTest1();
        job1.parentCustomJobId = 'parent1';
        job1.priority = 10;

        QueueableJobTest2 job2 = new QueueableJobTest2();
        job2.parentCustomJobId = 'parent2';
        job2.priority = 10;

        Integer result = job1.compareTo(job2);
        Assert.areEqual(0, result);
    }

    @IsTest
    static void shouldCompareJobsWithBothNullPriorities() {
        QueueableJobTest1 job1 = new QueueableJobTest1();
        job1.priority = null;

        QueueableJobTest2 job2 = new QueueableJobTest2();
        job2.priority = null;

        Integer result = job1.compareTo(job2);
        Assert.areEqual(0, result);
    }

    @IsTest
    static void shouldCompareJobsWithOnePriorityNull() {
        QueueableJobTest1 job1 = new QueueableJobTest1();
        job1.priority = 10;

        QueueableJobTest2 job2 = new QueueableJobTest2();
        job2.priority = null;

        Integer result = job1.compareTo(job2);
        Assert.areEqual(-1, result);

        result = job2.compareTo(job1);
        Assert.areEqual(1, result);
    }

    @IsTest
    static void shouldUseSchedulableBuilderWithStringCronExpression() {
        Test.startTest();
        Async.schedulable(new SchedulableTest())
            .name(TEST_SCHEDULABLE_JOB_NAME)
            .cronExpression('0 0 12 * * ?')
            .schedule();
        Test.stopTest();

        List<CronTrigger> triggers = [
            SELECT CronExpression
            FROM CronTrigger
            WHERE CronJobDetail.Name = :TEST_SCHEDULABLE_JOB_NAME
        ];
        Assert.areEqual(1, triggers.size());
        Assert.areEqual('0 0 12 * * ? *', triggers[0].CronExpression);
    }

    @IsTest
    static void shouldBuildEveryXMinutesCrons() {
        List<CronBuilder> crons = new CronBuilder().buildForEveryXMinutes(15);

        Assert.areEqual(4, crons.size());
        Assert.areEqual('0', crons[0].minute);
        Assert.areEqual('15', crons[1].minute);
        Assert.areEqual('30', crons[2].minute);
        Assert.areEqual('45', crons[3].minute);
    }

    @IsTest
    static void shouldScheduleWithBoundaryEveryXMinutes() {
        List<CronBuilder> crons30 = new CronBuilder().buildForEveryXMinutes(30);
        Assert.areEqual(2, crons30.size());

        List<CronBuilder> crons1 = new CronBuilder().buildForEveryXMinutes(1);
        Assert.areEqual(60, crons1.size());
    }

    @IsTest
    static void shouldTestFinalizerWithSuccessViaEnqueue() {
        AsyncMock.whenFinalizer('error-handler').thenReturn(ParentJobResult.SUCCESS);

        Test.startTest();
        Async.queueable(new ParentJobWithFinalizer('error-handler')).enqueue();
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Account]);
    }

    @IsTest
    static void shouldTestFinalizerWithExceptionViaEnqueue() {
        AsyncMock.whenFinalizer('error-handler').thenThrow(new DmlException('Parent job failed'));

        Test.startTest();
        Async.queueable(new ParentJobWithFinalizer('error-handler')).enqueue();
        Test.stopTest();

        Account errorLog = [SELECT Name, Description FROM Account LIMIT 1];
        Assert.areEqual('Error Log', errorLog.Name);
        Assert.areEqual('Parent job failed', errorLog.Description);
    }

    @IsTest
    static void shouldTestFinalizerDirectlyWithMockContext() {
        ErrorHandlerFinalizer finalizer = new ErrorHandlerFinalizer();
        finalizer.finalizerCtx = new AsyncMock.MockFinalizerContext()
            .setResult(ParentJobResult.UNHANDLED_EXCEPTION)
            .setException(new DmlException('Direct test error'));

        finalizer.work();

        Account errorLog = [SELECT Name, Description FROM Account LIMIT 1];
        Assert.areEqual('Error Log', errorLog.Name);
        Assert.areEqual('Direct test error', errorLog.Description);
    }

    @IsTest
    static void shouldTestQueueableWithMockContext() {
        AsyncMock.whenQueueable('account-creator').thenReturn(new AsyncMock.MockQueueableContext());

        Test.startTest();
        Async.queueable(new AccountCreatorJob('Test Account')).mockId('account-creator').enqueue();
        Test.stopTest();

        Account acc = [SELECT Name, Description FROM Account LIMIT 1];
        Assert.areEqual('Test Account', acc.Name);
        Assert.isNotNull(acc.Description);
    }

    @IsTest
    static void shouldTestQueueableDirectlyWithMockContext() {
        AccountCreatorJob job = new AccountCreatorJob('Direct Test');
        job.queueableCtx = new AsyncMock.MockQueueableContext();

        job.work();

        Account acc = [SELECT Name, Description FROM Account LIMIT 1];
        Assert.areEqual('Direct Test', acc.Name);
        Assert.isNotNull(acc.Description);
    }

    @IsTest
    static void shouldTestMultipleFinalizerInvocations() {
        AsyncMock.whenFinalizer('multi-test')
            .thenReturn(ParentJobResult.SUCCESS)
            .thenThrow(new DmlException('Second call failed'))
            .thenReturn(ParentJobResult.SUCCESS);

        Test.startTest();
        Async.queueable(new ParentJobWithFinalizer('multi-test')).enqueue();
        Async.queueable(new ParentJobWithFinalizer('multi-test')).enqueue();
        Async.queueable(new ParentJobWithFinalizer('multi-test')).enqueue();
        Test.stopTest();

        Assert.areEqual(1, [SELECT COUNT() FROM Account]);
        Assert.areEqual(
            'Second call failed',
            [SELECT Description FROM Account LIMIT 1].Description
        );
    }

    @IsTest
    static void shouldTestDefaultFinalizerMock() {
        AsyncMock.whenFinalizerDefault().thenReturn(ParentJobResult.SUCCESS);

        Test.startTest();
        Async.queueable(new ParentJobWithFinalizer('job-1')).enqueue();
        Async.queueable(new ParentJobWithFinalizer('job-2')).enqueue();
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Account]);
    }

    @IsTest
    static void shouldTestBatchJobExecuteDirectly() {
        Account testAcc = new Account(Name = 'Test');
        insert testAcc;

        AsyncMock.MockBatchableContext mockCtx = new AsyncMock.MockBatchableContext();

        AsyncTest batchJob = new AsyncTest();

        batchJob.execute(mockCtx, new List<Account>{ testAcc });

        Account updatedAcc = [SELECT Description FROM Account WHERE Id = :testAcc.Id];
        Assert.isTrue(updatedAcc.Description.startsWith('Processed by:'));
    }

    @IsTest
    static void shouldTestBatchJobFinishDirectly() {
        AsyncMock.MockBatchableContext mockCtx = new AsyncMock.MockBatchableContext();

        AsyncTest batchJob = new AsyncTest();
        batchJob.finish(mockCtx);

        Account finishLog = [SELECT Name, Description FROM Account LIMIT 1];
        Assert.areEqual('Batch Complete', finishLog.Name);
        Assert.isTrue(finishLog.Description.startsWith('Job:'));
    }

    @IsTest
    static void shouldTestSchedulableJobDirectly() {
        AsyncMock.MockSchedulableContext mockCtx = new AsyncMock.MockSchedulableContext();

        SchedulableForMockTest job = new SchedulableForMockTest();
        job.execute(mockCtx);

        Account acc = [SELECT Name, Description FROM Account LIMIT 1];
        Assert.areEqual('Scheduled Cleanup', acc.Name);
        Assert.isTrue(acc.Description.startsWith('Trigger:'));
    }

    @IsTest
    static void shouldResetMocks() {
        AsyncMock.whenFinalizer('test').thenReturn(ParentJobResult.SUCCESS);
        AsyncMock.whenQueueable('test').thenReturn(new AsyncMock.MockQueueableContext());
        AsyncMock.whenFinalizerDefault().thenReturn(ParentJobResult.SUCCESS);
        AsyncMock.whenQueueableDefault().thenReturn(new AsyncMock.MockQueueableContext());

        AsyncMock.reset();

        Assert.isNull(AsyncMock.getFinalizerContext('test'));
        Assert.isNull(AsyncMock.getQueueableContext('test'));
        Assert.isNull(AsyncMock.getFinalizerContext('unknown'));
        Assert.isNull(AsyncMock.getQueueableContext('unknown'));
    }

    @IsTest
    static void shouldReturnLastContextWhenMultipleConsumed() {
        AsyncMock.whenFinalizer('test')
            .thenReturn(ParentJobResult.SUCCESS)
            .thenThrow(new DmlException('Error'));

        FinalizerContext ctx1 = AsyncMock.getFinalizerContext('test');
        FinalizerContext ctx2 = AsyncMock.getFinalizerContext('test');
        FinalizerContext ctx3 = AsyncMock.getFinalizerContext('test');

        Assert.areEqual(ParentJobResult.SUCCESS, ctx1.getResult());
        Assert.areEqual(ParentJobResult.UNHANDLED_EXCEPTION, ctx2.getResult());
        Assert.areEqual(ParentJobResult.UNHANDLED_EXCEPTION, ctx3.getResult());
    }

    public Iterable<Account> start(Database.BatchableContext bc) {
        // This is just a placeholder to start the batch.
        return new List<Account>{ new Account() };
    }

    public void execute(Database.BatchableContext ctx, List<Account> scope) {
        for (Account acc : scope) {
            acc.Description = 'Processed by: ' + ctx.getJobId();
        }
        if (!scope.isEmpty() && scope[0].Id != null) {
            update scope;
        }
    }

    public void finish(Database.BatchableContext bc) {
        insert new Account(Name = 'Batch Complete', Description = 'Job: ' + bc.getJobId());
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
            insert new Account(
                Name = Async.getQueueableJobContext()?.currentJob?.uniqueName,
                Description = finalizerCtx?.getResult() == ParentJobResult.SUCCESS
                    ? 'Success'
                    : finalizerCtx?.getException()?.getMessage()
            );
        }
    }

    private class FinalizerErrorQueueableTest extends QueueableJob {
        public override void work() {
            Async.queueable(new SuccessfulQueueableTest()).attachFinalizer();
        }
    }

    private class ChainedQueueableJob extends QueueableJob {
        private Integer chainDepthLimit = 1;
        private Integer currentChainDepth = 0;

        public ChainedQueueableJob(Integer chainDepthLimit) {
            this.chainDepthLimit = chainDepthLimit;
        }

        public override void work() {
            currentChainDepth++;
            insert new Account(Name = Async.getQueueableJobContext()?.currentJob?.uniqueName);
            if (currentChainDepth < chainDepthLimit) {
                Async.queueable(this).enqueue();
            }
        }
    }

    public class QueueableJobTest1 extends QueueableJob {
        public QueueableJobTest2 complexMember = new QueueableJobTest2();
        public override void work() {
        }
    }

    private class QueueableJobTest2 extends QueueableJob {
        public String primitiveMember = PRIMITIVE_VALUE_INITIAL;
        public override void work() {
        }
    }

    private class QueueableJobTest3 extends QueueableJob {
        public override void work() {
        }
    }

    private class QueueableJobTest4 extends QueueableJob {
        public override void work() {
        }
    }

    private class QueueableJobTest5 extends QueueableJob {
        public override void work() {
        }
    }

    private class QueueableJobTest6 extends QueueableJob {
        public override void work() {
        }
    }

    private class QueueableJobTest7 extends QueueableJob {
        public override void work() {
        }
    }

    private class QueueableJobTest8 extends QueueableJob {
        public override void work() {
        }
    }

    private class SchedulableTest implements Schedulable {
        public void execute(SchedulableContext ctx) {
        }
    }

    private class CustomException extends Exception {
    }

    public class ParentJobWithFinalizer extends QueueableJob {
        private String mockId;

        public ParentJobWithFinalizer(String mockId) {
            this.mockId = mockId;
        }

        public override void work() {
            Async.queueable(new ErrorHandlerFinalizer()).mockId(mockId).attachFinalizer();
        }
    }

    public class ErrorHandlerFinalizer extends QueueableJob.Finalizer {
        public override void work() {
            FinalizerContext ctx = this.finalizerCtx;
            if (ctx?.getResult() == ParentJobResult.UNHANDLED_EXCEPTION) {
                insert new Account(
                    Name = 'Error Log',
                    Description = ctx.getException()?.getMessage()
                );
            }
        }
    }

    public class AccountCreatorJob extends QueueableJob {
        private String accountName;

        public AccountCreatorJob(String accountName) {
            this.accountName = accountName;
        }

        public override void work() {
            Id jobId = this.queueableCtx?.getJobId();
            insert new Account(Name = accountName, Description = 'Job: ' + jobId);
        }
    }

    private class SchedulableForMockTest implements Schedulable {
        public void execute(SchedulableContext sc) {
            insert new Account(
                Name = 'Scheduled Cleanup',
                Description = 'Trigger: ' + sc.getTriggerId()
            );
        }
    }
}
