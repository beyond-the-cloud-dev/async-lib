/**
 * PMD False Positives:
 * - ApexAssertionsShouldIncludeMessage: IMO not all assertions need a message
 * - EmptyStatementBlock: It is test class, some methods are just to create jobs placeholders
 * - NcssTypeCount: It is a library and all of its tests live in ONE test class
 * - NcssCount: It is a library and all of its tests live in ONE test class
 **/
@SuppressWarnings(
    'PMD.ApexAssertionsShouldIncludeMessage,PMD.EmptyStatementBlock,PMD.NcssTypeCount,PMD.NcssCount'
)
@IsTest
@TestVisible
private class AsyncTest implements Database.Batchable<SObject> {
    private static final String ACCOUNT_NAME = 'Test Account';
    private static final String CUSTOM_ERROR_MESSAGE = 'Something goes wrong.';
    private static final String DUPLICATE_SIGNATURE_ERROR_MESSAGE = 'Attempt to enqueue job with duplicate queueable signature';
    private static final String TEST_SIGNATURE_NAME = 'SignatureName';
    private static final String TEST_SCHEDULABLE_JOB_NAME = 'SchedulableTestJob';
    private static final String PRIMITIVE_VALUE_INITIAL = 'INITIAL_VALUE';
    private static final String CHUNK_PROCESSED = 'CHUNK_PROCESSED';

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
            getClassNameWithNamespaceDotPrefix(
                'AsyncTest.QueueableJobTest1'
            ) => new QueueableJobSetting__mdt(
                DeveloperName = getClassNameWithNamespaceDotPrefix('AsyncTest.QueueableJobTest1'),
                IsDisabled__c = true
            ),
            getClassNameWithNamespaceDotPrefix(
                'AsyncTest.QueueableJobTest7'
            ) => new QueueableJobSetting__mdt(
                DeveloperName = getClassNameWithNamespaceDotPrefix('AsyncTest.QueueableJobTest7'),
                IsDisabled__c = false
            ),
            getClassNameWithNamespaceDotPrefix(
                'AsyncTest.QueueableJobTest8'
            ) => new QueueableJobSetting__mdt(
                DeveloperName = getClassNameWithNamespaceDotPrefix('AsyncTest.QueueableJobTest8'),
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
            getClassNameWithNamespaceDotPrefix(
                'AsyncTest.QueueableJobTest1'
            ) => new QueueableJobSetting__mdt(
                DeveloperName = getClassNameWithNamespaceDotPrefix('AsyncTest.QueueableJobTest1'),
                CreateResult__c = true
            )
        };
        QueueableChain chain2 = new QueueableChain();
        chain2.queueableJobSettingByJobName = new Map<String, QueueableJobSetting__mdt>{
            getClassNameWithNamespaceDotPrefix(
                'AsyncTest.QueueableJobTest1'
            ) => new QueueableJobSetting__mdt(
                DeveloperName = getClassNameWithNamespaceDotPrefix('AsyncTest.QueueableJobTest1'),
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
    static void shouldEnqueueNothingForEmptyBuilder() {
        Test.startTest();
        Async.Result result = Async.queueable().enqueue();
        Test.stopTest();

        Assert.areEqual(
            0,
            [
                SELECT COUNT()
                FROM AsyncApexJob
                WHERE JobType = 'Queueable' AND ApexClass.Name = 'AsyncTest'
            ],
            'No queueable should be enqueued from an empty builder.'
        );
        Assert.areEqual(null, result.salesforceJobId, 'No salesforceJobId expected.');
        Assert.areEqual(
            0,
            result.queueableChainState.jobs.size(),
            'Chain state should report zero jobs.'
        );
    }

    @IsTest
    static void shouldEnqueueSingleJobAddedViaChainOnEmptyBuilder() {
        QueueableJobTest1 job1 = new QueueableJobTest1();

        Test.startTest();
        Async.Result result = Async.queueable().chain(job1).enqueue();
        Test.stopTest();

        Assert.areEqual(
            1,
            result.queueableChainState.jobs.size(),
            'Chain should contain the single added job.'
        );
        Assert.areNotEqual(null, result.salesforceJobId, 'A job should have been enqueued.');
    }

    @IsTest
    static void shouldEnqueueMultipleJobsAddedViaRepeatedChainOnEmptyBuilder() {
        QueueableJobTest1 job1 = new QueueableJobTest1();
        QueueableJobTest2 job2 = new QueueableJobTest2();
        QueueableJobTest3 job3 = new QueueableJobTest3();

        Test.startTest();
        QueueableBuilder builder = Async.queueable();
        builder.chain(job1);
        builder.chain(job2);
        builder.chain(job3);
        Async.Result result = builder.enqueue();
        Test.stopTest();

        Assert.areEqual(
            3,
            result.queueableChainState.jobs.size(),
            'Chain should contain all three jobs in the order they were added.'
        );
    }

    @IsTest
    static void shouldOnlyChainBranchesThatMatchConditionOnEmptyBuilder() {
        QueueableJobTest1 job1 = new QueueableJobTest1();
        QueueableJobTest2 job2 = new QueueableJobTest2();
        QueueableJobTest3 job3 = new QueueableJobTest3();
        Boolean addJob1 = true;
        Boolean addJob2 = false;
        Boolean addJob3 = true;

        Test.startTest();
        QueueableBuilder builder = Async.queueable();
        if (addJob1) {
            builder.chain(job1);
        }
        if (addJob2) {
            builder.chain(job2);
        }
        if (addJob3) {
            builder.chain(job3);
        }
        Async.Result result = builder.enqueue();
        Test.stopTest();

        Assert.areEqual(
            2,
            result.queueableChainState.jobs.size(),
            'Only branches whose condition was true should be in the chain.'
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
    static void shouldReturnFirstEnqueuedJobIdWhenEnqueueAfterChainBuilder() {
        QueueableJobTest1 job1 = new QueueableJobTest1();
        QueueableJobTest2 job2 = new QueueableJobTest2();

        Test.startTest();
        Async.Result ar = Async.queueable(job1).chain(job2).enqueue();
        Test.stopTest();

        Assert.isNotNull(ar);
        Assert.isNotNull(
            ar.salesforceJobId,
            'salesforceJobId must reflect the job that was actually enqueued, not the last builder argument'
        );
        Assert.areEqual(Async.AsyncType.QUEUEABLE, ar.asyncType);
        Assert.isNotNull(ar.queueableChainState);
        Assert.areEqual(2, ar.queueableChainState.jobs.size());
        Assert.areEqual(
            ar.salesforceJobId,
            ar.queueableChainState.jobs.get(0).salesforceJobId,
            'Result salesforceJobId must match the first job in the chain state'
        );
    }

    @IsTest
    static void shouldReturnFirstEnqueuedJobIdAfterMultipleChainCallsBeforeEnqueue() {
        QueueableJobTest1 job1 = new QueueableJobTest1();
        QueueableJobTest2 job2 = new QueueableJobTest2();
        QueueableJobTest3 job3 = new QueueableJobTest3();

        Async.queueable(job1).chain();
        Async.queueable(job2).chain();

        Test.startTest();
        Async.Result ar = Async.queueable(job3).enqueue();
        Test.stopTest();

        Assert.isNotNull(ar);
        Assert.isNotNull(
            ar.salesforceJobId,
            'salesforceJobId must be non-null when chain has accumulated jobs before enqueue'
        );
        Assert.isNotNull(ar.queueableChainState);
        Assert.areEqual(3, ar.queueableChainState.jobs.size());
    }

    @IsTest
    static void shouldReturnEmptyListWhenScheduleSkippedDueToDuplicate() {
        SuccessfulQueueableTest job = new SuccessfulQueueableTest();
        String name = 'RegressionTest_SkipDuplicate_' + System.currentTimeMillis();

        Test.startTest();
        List<Async.Result> first = Async.queueable(job)
            .asSchedulable()
            .name(name)
            .cronExpression(new CronBuilder().everyDay(23, 58))
            .skipWhenAlreadyScheduled()
            .schedule();

        List<Async.Result> second = Async.queueable(job)
            .asSchedulable()
            .name(name)
            .cronExpression(new CronBuilder().everyDay(23, 58))
            .skipWhenAlreadyScheduled()
            .schedule();
        Test.stopTest();

        Assert.isNotNull(first);
        Assert.areEqual(1, first.size());
        Assert.isNotNull(
            second,
            'schedule() with skipWhenAlreadyScheduled must return an empty list, not null, when the job already exists'
        );
        Assert.isTrue(second.isEmpty());
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
    static void shouldReturnNullWhenAllMocksConsumed() {
        AsyncMock.whenFinalizer('test')
            .thenReturn(ParentJobResult.SUCCESS)
            .thenThrow(new DmlException('Error'));

        FinalizerContext ctx1 = AsyncMock.getFinalizerContext('test');
        FinalizerContext ctx2 = AsyncMock.getFinalizerContext('test');
        FinalizerContext ctx3 = AsyncMock.getFinalizerContext('test');

        Assert.areEqual(ParentJobResult.SUCCESS, ctx1.getResult());
        Assert.areEqual(ParentJobResult.UNHANDLED_EXCEPTION, ctx2.getResult());
        Assert.isNull(ctx3);
    }

    @IsTest
    static void shouldUseDefaultMockWhenSpecificMocksConsumed() {
        AsyncMock.whenFinalizerDefault().thenReturn(ParentJobResult.SUCCESS);
        AsyncMock.whenFinalizer('test').thenThrow(new DmlException('Error'));

        FinalizerContext ctx1 = AsyncMock.getFinalizerContext('test');
        FinalizerContext ctx2 = AsyncMock.getFinalizerContext('test');

        Assert.areEqual(ParentJobResult.UNHANDLED_EXCEPTION, ctx1.getResult());
        Assert.areEqual(ParentJobResult.SUCCESS, ctx2.getResult());
    }

    @IsTest
    private static void shouldComputeFixedBackoff() {
        Backoff policy = Backoff.fixed(3);
        Assert.areEqual(3, policy.delayMinutes(1));
        Assert.areEqual(3, policy.delayMinutes(5));
        Assert.areEqual(
            10,
            Backoff.fixed(20).delayMinutes(1),
            'Delay must be capped at 10 minutes.'
        );
    }

    @IsTest
    private static void shouldComputeExponentialBackoff() {
        Backoff policy = Backoff.exponential(1);
        Assert.areEqual(1, policy.delayMinutes(1));
        Assert.areEqual(2, policy.delayMinutes(2));
        Assert.areEqual(4, policy.delayMinutes(3));
        Assert.areEqual(8, policy.delayMinutes(4));
        Assert.areEqual(10, policy.delayMinutes(5), 'Should be capped at 10 minutes.');
        Assert.areEqual(10, policy.delayMinutes(9), 'Should stay capped at 10 minutes.');
    }

    @IsTest
    private static void shouldComputeExponentialJitterWithinBounds() {
        Backoff policy = Backoff.exponentialWithJitter(2);
        for (Integer attempt = 1; attempt <= 6; attempt++) {
            Integer delay = policy.delayMinutes(attempt);
            Assert.isTrue(delay >= 0, 'Delay must be non-negative.');
            Assert.isTrue(delay <= 10, 'Delay must be capped at 10 minutes.');
        }
    }

    @IsTest
    private static void shouldBuildBackoffFromName() {
        Assert.isNotNull(Backoff.fromName('EXPONENTIAL', 2));
        Assert.isNotNull(Backoff.fromName('fixed', 2));
        Assert.isNull(Backoff.fromName('NOT_A_STRATEGY', 2));
        Assert.isNull(Backoff.fromName(null, 2));
    }

    @IsTest
    private static void shouldThrowOnNegativeBackoffBase() {
        try {
            Backoff.fixed(-1);
            Assert.fail('Should reject a negative base.');
        } catch (Async.IllegalArgumentException ex) {
            Assert.isTrue(ex.getMessage().contains('non-negative'));
        }
    }

    @IsTest
    private static void shouldRetryOnAnyExceptionByDefault() {
        QueueableJobTest1 job = new QueueableJobTest1();
        job.maxRetries = 2;
        job.recordFailure(new CustomException('boom'));

        Assert.isTrue(job.canRetry());
        Assert.areEqual('boom', job.failure.message, 'Failure metadata is captured.');
    }

    @IsTest
    private static void shouldMatchAnyTypeWhenNoFilter() {
        QueueableJobTest1 job = new QueueableJobTest1();

        Assert.isTrue(
            job.matchesRetryOnTypes('System.LimitException'),
            'With no retryOn filter, every type matches.'
        );
    }

    @IsTest
    private static void shouldMatchWhitelistedType() {
        QueueableJobTest1 job = new QueueableJobTest1();
        job.retryOnExceptionTypes = new Set<String>{ 'System.LimitException' };

        Assert.isTrue(job.matchesRetryOnTypes('System.LimitException'));
    }

    @IsTest
    private static void shouldNotMatchTypeOutsideWhitelist() {
        QueueableJobTest1 job = new QueueableJobTest1();
        job.maxRetries = 3;
        job.retryOnExceptionTypes = new Set<String>{ 'System.DmlException' };

        Assert.isFalse(job.matchesRetryOnTypes('System.CalloutException'));

        job.recordFailure(new CustomException('outside whitelist'));
        Assert.isFalse(job.canRetry(), 'Type outside the allowlist must not retry.');
    }

    @IsTest
    private static void shouldMatchTypeByShortName() {
        QueueableJobTest1 job = new QueueableJobTest1();
        job.retryOnExceptionTypes = new Set<String>{ 'DmlException' };

        Assert.isTrue(job.matchesRetryOnTypes('System.DmlException'));
    }

    @IsTest
    private static void shouldNotRetryWhenAttemptsExhausted() {
        QueueableJobTest1 job = new QueueableJobTest1();
        job.maxRetries = 2;
        job.recordFailure(new CustomException('boom'));
        job.retryAttempt = 2;

        Assert.isFalse(job.canRetry());
    }

    @IsTest
    private static void shouldNotRetryWhenNotFailed() {
        QueueableJobTest1 job = new QueueableJobTest1();
        job.maxRetries = 2;

        Assert.isFalse(job.canRetry());
    }

    @IsTest
    private static void shouldVetoRetryViaIsRetryableOverride() {
        NonRetryableJob job = new NonRetryableJob();
        job.maxRetries = 3;
        job.recordFailure(new CustomException('boom'));

        Assert.isFalse(job.retryDecision, 'Override vetoed the retry.');
        Assert.isFalse(job.canRetry());
    }

    @IsTest
    private static void shouldRequireBothRetryOnAndIsRetryable() {
        MessageVetoJob typeMatchedButVetoed = new MessageVetoJob();
        typeMatchedButVetoed.maxRetries = 2;
        typeMatchedButVetoed.retryOnExceptionTypes = new Set<String>{ 'CustomException' };
        typeMatchedButVetoed.recordFailure(new CustomException('permanent failure'));
        Assert.isFalse(
            typeMatchedButVetoed.canRetry(),
            'Type matched but isRetryable vetoed by message — AND blocks.'
        );

        MessageVetoJob bothPass = new MessageVetoJob();
        bothPass.maxRetries = 2;
        bothPass.retryOnExceptionTypes = new Set<String>{ 'CustomException' };
        bothPass.recordFailure(new CustomException('transient blip'));
        Assert.isTrue(bothPass.canRetry(), 'Both gates pass.');

        MessageVetoJob typeExcluded = new MessageVetoJob();
        typeExcluded.maxRetries = 2;
        typeExcluded.retryOnExceptionTypes = new Set<String>{ 'System.DmlException' };
        typeExcluded.recordFailure(new CustomException('transient blip'));
        Assert.isFalse(
            typeExcluded.canRetry(),
            'retryOn excluded the type; AND can only narrow, never broaden.'
        );
    }

    @IsTest
    private static void shouldNotRetryWhenIsRetryableOverrideThrows() {
        ThrowingClassifierJob job = new ThrowingClassifierJob();
        job.maxRetries = 2;
        job.recordFailure(new CustomException('original'));

        Assert.isFalse(job.retryDecision, 'A throwing classifier must not retry.');
        Assert.isFalse(job.canRetry());
        Assert.isTrue(
            String.isNotBlank(job.retryHistory),
            'The override failure is recorded in retry history.'
        );
    }

    @IsTest
    private static void shouldClassifyUncatchableExceptionFromFinalizer() {
        SuccessfulQueueableTest job = new SuccessfulQueueableTest();
        QueueableChain chain = new QueueableChain();
        chain.addJob(job);
        job.maxRetries = 1;
        QueueableManager.get().setChain(chain);

        Test.startTest();
        chain.executeCurrentJob(new AsyncMock.MockQueueableContext());
        chain.enqueueNextJobIfAnyFromFinalizer(
            new AsyncMock.MockFinalizerContext().setException(new CustomException('uncatchable'))
        );
        Test.stopTest();

        Assert.isTrue(job.hasFailed, 'Reconcile marks the job failed from the finalizer.');
        Assert.areEqual(
            'uncatchable',
            job.failure.message,
            'Exception captured from the finalizer.'
        );
        Assert.areEqual(2, chain.jobs.size(), 'A finalizer-detected failure enqueues a retry.');
    }

    @IsTest
    private static void shouldRetryUnknownFailureWhenNoTypeFilter() {
        SuccessfulQueueableTest job = new SuccessfulQueueableTest();
        QueueableChain chain = new QueueableChain();
        chain.addJob(job);
        job.maxRetries = 1;
        QueueableManager.get().setChain(chain);

        Test.startTest();
        chain.executeCurrentJob(new AsyncMock.MockQueueableContext());
        chain.enqueueNextJobIfAnyFromFinalizer(
            new AsyncMock.MockFinalizerContext().setResult(ParentJobResult.UNHANDLED_EXCEPTION)
        );
        Test.stopTest();

        Assert.areEqual(
            2,
            chain.jobs.size(),
            'No type filter: an unidentifiable failure is retried by default policy.'
        );
    }

    @IsTest
    private static void shouldNotRetryUnknownFailureWhenTypeFilterSet() {
        SuccessfulQueueableTest job = new SuccessfulQueueableTest();
        QueueableChain chain = new QueueableChain();
        chain.addJob(job);
        job.maxRetries = 1;
        job.retryOnExceptionTypes = new Set<String>{ 'System.DmlException' };
        QueueableManager.get().setChain(chain);

        Test.startTest();
        chain.executeCurrentJob(new AsyncMock.MockQueueableContext());
        chain.enqueueNextJobIfAnyFromFinalizer(
            new AsyncMock.MockFinalizerContext().setResult(ParentJobResult.UNHANDLED_EXCEPTION)
        );
        Test.stopTest();

        Assert.isTrue(job.hasFailed);
        Assert.areEqual(
            1,
            chain.jobs.size(),
            'Type filter set but failure unidentifiable: cannot confirm membership, so no retry.'
        );
    }

    @IsTest
    private static void shouldRunResetForRetryOnRetryClone() {
        ResettableRetryJob job = new ResettableRetryJob();
        QueueableChain chain = new QueueableChain();
        chain.addJob(job);
        job.maxRetries = 2;
        job.continueOnJobExecuteFail = true;
        QueueableManager.get().setChain(chain);

        Test.startTest();
        chain.executeCurrentJob(new AsyncMock.MockQueueableContext());
        chain.enqueueNextJobIfAnyFromFinalizer(
            new AsyncMock.MockFinalizerContext().setResult(ParentJobResult.SUCCESS)
        );
        Test.stopTest();

        Assert.areEqual(2, chain.jobs.size(), 'A retry clone should have been inserted.');
        Assert.isTrue(
            ((ResettableRetryJob) chain.jobs[0]).wasReset,
            'resetForRetry() must run on the retry clone.'
        );
    }

    @IsTest
    private static void shouldRejectNegativeRetryCount() {
        try {
            Async.queueable(new QueueableJobTest1()).retry(-1);
            Assert.fail('Should reject a negative retry count.');
        } catch (Exception ex) {
            Assert.areEqual(QueueableManager.ERROR_MESSAGE_INVALID_MAX_RETRIES, ex.getMessage());
        }
    }

    @IsTest
    private static void shouldRejectRetryCountAboveCap() {
        try {
            Async.queueable(new QueueableJobTest1()).retry(QueueableManager.MAX_RETRY_CAP + 1);
            Assert.fail('Should reject a retry count above the framework cap.');
        } catch (Exception ex) {
            Assert.areEqual(
                QueueableManager.ERROR_MESSAGE_MAX_RETRIES_EXCEEDS_CAP,
                ex.getMessage()
            );
        }
    }

    @IsTest
    private static void shouldRegisterRetryOnExceptionTypes() {
        Test.startTest();
        Async.Result result = Async.queueable(new QueueableJobTest1())
            .retry(2)
            .retryOn(DmlException.class)
            .retryOn(CalloutException.class)
            .enqueue();
        Test.stopTest();

        Assert.areEqual(2, result.job.retryOnExceptionTypes.size());
    }

    @IsTest
    private static void shouldApplyRetryDefaultsFromCmdt() {
        QueueableJobTest1 job = new QueueableJobTest1();

        QueueableChain chain = new QueueableChain();
        chain.queueableJobSettingByJobName = new Map<String, QueueableJobSetting__mdt>{
            QueueableManager.QUEUEABLE_JOB_SETTING_ALL => new QueueableJobSetting__mdt(
                DeveloperName = QueueableManager.QUEUEABLE_JOB_SETTING_ALL,
                MaxRetries__c = 3,
                BackoffStrategy__c = 'EXPONENTIAL',
                BackoffBaseMinutes__c = 2,
                RetryableExceptions__c = 'System.DmlException, System.CalloutException'
            )
        };
        chain.addJob(job);

        Assert.areEqual(3, job.maxRetries);
        Assert.isNotNull(job.backoff);
        Assert.areEqual(2, job.retryOnExceptionTypes.size());
        Assert.isTrue(job.retryOnExceptionTypes.contains('System.DmlException'));
    }

    @IsTest
    private static void shouldNotOverrideExplicitRetryWithCmdt() {
        QueueableJobTest1 job = new QueueableJobTest1();
        job.maxRetries = 5;

        QueueableChain chain = new QueueableChain();
        chain.queueableJobSettingByJobName = new Map<String, QueueableJobSetting__mdt>{
            QueueableManager.QUEUEABLE_JOB_SETTING_ALL => new QueueableJobSetting__mdt(
                DeveloperName = QueueableManager.QUEUEABLE_JOB_SETTING_ALL,
                MaxRetries__c = 3
            )
        };
        chain.addJob(job);

        Assert.areEqual(5, job.maxRetries, 'Explicit fluent config must win over CMDT.');
    }

    @IsTest
    private static void shouldRejectCmdtMaxRetriesAboveCap() {
        QueueableJobTest1 job = new QueueableJobTest1();

        QueueableChain chain = new QueueableChain();
        chain.queueableJobSettingByJobName = new Map<String, QueueableJobSetting__mdt>{
            QueueableManager.QUEUEABLE_JOB_SETTING_ALL => new QueueableJobSetting__mdt(
                DeveloperName = QueueableManager.QUEUEABLE_JOB_SETTING_ALL,
                MaxRetries__c = QueueableManager.MAX_RETRY_CAP + 1
            )
        };

        try {
            chain.addJob(job);
            Assert.fail('Should reject a CMDT retry count above the framework cap.');
        } catch (Exception ex) {
            Assert.areEqual(
                QueueableManager.ERROR_MESSAGE_MAX_RETRIES_EXCEEDS_CAP,
                ex.getMessage()
            );
        }
    }

    @IsTest
    private static void shouldReEnqueueRetryJobOnFailure() {
        FailureQueueableTest job = new FailureQueueableTest();

        QueueableChain chain = new QueueableChain();
        chain.addJob(job);
        job.maxRetries = 2;
        job.backoff = Backoff.fixed(5);
        job.continueOnJobExecuteFail = true;
        QueueableManager.get().setChain(chain);

        Test.startTest();
        chain.executeCurrentJob(new AsyncMock.MockQueueableContext());
        chain.enqueueNextJobIfAnyFromFinalizer(
            new AsyncMock.MockFinalizerContext().setResult(ParentJobResult.SUCCESS)
        );
        Test.stopTest();

        Assert.areEqual(2, chain.jobs.size(), 'A retry clone should have been inserted.');
        Assert.areEqual(1, chain.jobs[0].retryAttempt);
        Assert.areEqual(5, chain.jobs[0].delay, 'Backoff delay should be applied to the retry.');
        Assert.isTrue(
            String.isNotBlank(chain.jobs[0].retryHistory),
            'Retry history should be recorded.'
        );
    }

    @IsTest
    private static void shouldRetryFailedQueueableUntilExhausted() {
        Assert.areEqual(0, [SELECT COUNT() FROM Account]);

        Test.startTest();
        Async.queueable(new FailureQueueableTest()).continueOnJobExecuteFail().retry(2).enqueue();
        Test.stopTest();

        Assert.areEqual(
            3,
            [SELECT COUNT() FROM Account],
            'Original run plus 2 retries should each execute work() once.'
        );
    }

    @IsTest
    private static void shouldNotRetryWhenNotConfigured() {
        Assert.areEqual(0, [SELECT COUNT() FROM Account]);

        Test.startTest();
        Async.queueable(new FailureQueueableTest()).continueOnJobExecuteFail().enqueue();
        Test.stopTest();

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Account],
            'No retry config means a single execution.'
        );
    }

    private static Async.Dependency dependencyOn(String customJobId, Async.Outcome outcome) {
        Async.Dependency dependency = new Async.Dependency();
        dependency.resolvedTargetCustomJobId = customJobId;
        dependency.requiredOutcome = outcome;
        return dependency;
    }

    @IsTest
    private static void shouldRunDependentJobWhenRequiredOutcomeMatches() {
        SuccessfulQueueableTest jobA = new SuccessfulQueueableTest();
        SuccessfulQueueableTest jobB = new SuccessfulQueueableTest();

        QueueableChain chain = new QueueableChain();
        chain.addJob(jobA);
        jobB.dependencies = new List<Async.Dependency>{
            dependencyOn(jobA.customJobId, Async.Outcome.SUCCESS)
        };
        chain.addJob(jobB);
        QueueableManager.get().setChain(chain);

        Test.startTest();
        chain.executeCurrentJob(new AsyncMock.MockQueueableContext());
        chain.enqueueNextJobIfAnyFromFinalizer(
            new AsyncMock.MockFinalizerContext().setResult(ParentJobResult.SUCCESS)
        );
        Test.stopTest();

        Assert.isFalse(jobB.isProcessed, 'Dependent job should not be skipped.');
        Assert.isNotNull(jobB.salesforceJobId, 'Dependent job should be enqueued.');
    }

    @IsTest
    private static void shouldSkipDependentJobWhenRequiredOutcomeMismatches() {
        FailureQueueableTest jobA = new FailureQueueableTest();
        jobA.continueOnJobExecuteFail = true;
        SuccessfulQueueableTest jobB = new SuccessfulQueueableTest();

        QueueableChain chain = new QueueableChain();
        chain.addJob(jobA);
        jobB.dependencies = new List<Async.Dependency>{
            dependencyOn(jobA.customJobId, Async.Outcome.SUCCESS)
        };
        chain.addJob(jobB);
        QueueableManager.get().setChain(chain);

        Test.startTest();
        chain.executeCurrentJob(new AsyncMock.MockQueueableContext());
        chain.enqueueNextJobIfAnyFromFinalizer(
            new AsyncMock.MockFinalizerContext().setResult(ParentJobResult.UNHANDLED_EXCEPTION)
        );
        Test.stopTest();

        Assert.isTrue(
            jobB.isProcessed,
            'Dependent job should be skipped when its dependency failed.'
        );
        Assert.isNull(jobB.salesforceJobId, 'Skipped job should not be enqueued.');
    }

    @IsTest
    private static void shouldRunCompensationJobWhenDependencyFails() {
        FailureQueueableTest jobA = new FailureQueueableTest();
        jobA.continueOnJobExecuteFail = true;
        SuccessfulQueueableTest compensation = new SuccessfulQueueableTest();

        QueueableChain chain = new QueueableChain();
        chain.addJob(jobA);
        compensation.dependencies = new List<Async.Dependency>{
            dependencyOn(jobA.customJobId, Async.Outcome.FAILURE)
        };
        chain.addJob(compensation);
        QueueableManager.get().setChain(chain);

        Test.startTest();
        chain.executeCurrentJob(new AsyncMock.MockQueueableContext());
        chain.enqueueNextJobIfAnyFromFinalizer(
            new AsyncMock.MockFinalizerContext().setResult(ParentJobResult.UNHANDLED_EXCEPTION)
        );
        Test.stopTest();

        Assert.isFalse(
            compensation.isProcessed,
            'Compensation job should run when dependency failed.'
        );
        Assert.isNotNull(compensation.salesforceJobId, 'Compensation job should be enqueued.');
    }

    @IsTest
    private static void shouldRunFinishedDependencyRegardlessOfOutcome() {
        FailureQueueableTest jobA = new FailureQueueableTest();
        jobA.continueOnJobExecuteFail = true;
        SuccessfulQueueableTest jobB = new SuccessfulQueueableTest();

        QueueableChain chain = new QueueableChain();
        chain.addJob(jobA);
        jobB.dependencies = new List<Async.Dependency>{
            dependencyOn(jobA.customJobId, Async.Outcome.COMPLETED)
        };
        chain.addJob(jobB);
        QueueableManager.get().setChain(chain);

        Test.startTest();
        chain.executeCurrentJob(new AsyncMock.MockQueueableContext());
        chain.enqueueNextJobIfAnyFromFinalizer(
            new AsyncMock.MockFinalizerContext().setResult(ParentJobResult.UNHANDLED_EXCEPTION)
        );
        Test.stopTest();

        Assert.isFalse(jobB.isProcessed, 'finished() should match a failed dependency.');
        Assert.isNotNull(jobB.salesforceJobId);
    }

    @IsTest
    private static void shouldCascadeSkipToTransitiveDependents() {
        FailureQueueableTest jobA = new FailureQueueableTest();
        jobA.continueOnJobExecuteFail = true;
        SuccessfulQueueableTest jobB = new SuccessfulQueueableTest();
        SuccessfulQueueableTest jobC = new SuccessfulQueueableTest();

        QueueableChain chain = new QueueableChain();
        chain.addJob(jobA);
        jobB.dependencies = new List<Async.Dependency>{
            dependencyOn(jobA.customJobId, Async.Outcome.SUCCESS)
        };
        chain.addJob(jobB);
        jobC.dependencies = new List<Async.Dependency>{
            dependencyOn(jobB.customJobId, Async.Outcome.SUCCESS)
        };
        chain.addJob(jobC);
        QueueableManager.get().setChain(chain);

        Test.startTest();
        chain.executeCurrentJob(new AsyncMock.MockQueueableContext());
        chain.enqueueNextJobIfAnyFromFinalizer(
            new AsyncMock.MockFinalizerContext().setResult(ParentJobResult.UNHANDLED_EXCEPTION)
        );
        Test.stopTest();

        Assert.isTrue(jobB.isProcessed, 'B skipped because A failed.');
        Assert.isTrue(jobC.isProcessed, 'C skipped because B never ran.');
        Assert.isNull(jobC.salesforceJobId);
    }

    @IsTest
    private static void shouldResolveAfterPreviousToPriorJob() {
        Async.Result result = Async.queueable(new SuccessfulQueueableTest())
            .chain(new SuccessfulQueueableTest())
            .dependsOn(Async.afterPrevious().succeeded())
            .chain();

        QueueableJob dependent = result.queueableChainState.jobs[1];
        Assert.areEqual(1, dependent.dependencies.size());
        Assert.isTrue(dependent.dependencies[0].previous);
        Assert.areEqual(
            result.queueableChainState.jobs[0].customJobId,
            dependent.dependencies[0].resolvedTargetCustomJobId,
            'afterPrevious() should resolve to the preceding job.'
        );
    }

    @IsTest
    private static void shouldResolveAfterResultToTargetJob() {
        Async.Result first = Async.queueable(new SuccessfulQueueableTest()).chain();
        Async.Result result = Async.queueable(new SuccessfulQueueableTest())
            .dependsOn(Async.after(first).succeeded())
            .chain();

        QueueableJob dependent = result.queueableChainState.jobs[1];
        Assert.areEqual(
            first.customJobId,
            dependent.dependencies[0].resolvedTargetCustomJobId,
            'after(Result) should resolve to the dependency job customJobId.'
        );
    }

    @IsTest
    private static void shouldRejectAfterPreviousWithoutPriorJob() {
        try {
            Async.queueable(new SuccessfulQueueableTest())
                .dependsOn(Async.afterPrevious().succeeded());
            Assert.fail('Should reject afterPrevious() with no preceding job.');
        } catch (Exception ex) {
            Assert.areEqual(
                QueueableManager.ERROR_MESSAGE_DEPENDS_ON_PREVIOUS_WITHOUT_JOB,
                ex.getMessage()
            );
        }
    }

    @IsTest
    private static void shouldRejectDependencyWithoutOutcome() {
        try {
            Async.queueable(new SuccessfulQueueableTest()).dependsOn(Async.after('a'));
            Assert.fail('Should reject a dependency missing a required outcome.');
        } catch (Exception ex) {
            Assert.areEqual(QueueableManager.ERROR_MESSAGE_INVALID_DEPENDENCY, ex.getMessage());
        }
    }

    @IsTest
    private static void shouldRollbackAndContinueWhenOnlyRollbackFlagSet() {
        Test.startTest();
        Async.queueable(new FailureQueueableTest())
            .rollbackOnJobExecuteFail()
            .chain(new SuccessfulQueueableTest())
            .enqueue();
        Test.stopTest();

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Account],
            'Failing job DML rolled back; chain continued to the next job, which committed.'
        );
    }

    @IsTest
    private static void shouldReconcileOutcomeFromFinalizerContext() {
        SuccessfulQueueableTest jobA = new SuccessfulQueueableTest();
        SuccessfulQueueableTest compensation = new SuccessfulQueueableTest();

        QueueableChain chain = new QueueableChain();
        chain.addJob(jobA);
        compensation.dependencies = new List<Async.Dependency>{
            dependencyOn(jobA.customJobId, Async.Outcome.FAILURE)
        };
        chain.addJob(compensation);
        QueueableManager.get().setChain(chain);

        Test.startTest();
        chain.executeCurrentJob(new AsyncMock.MockQueueableContext());
        chain.enqueueNextJobIfAnyFromFinalizer(
            new AsyncMock.MockFinalizerContext().setResult(ParentJobResult.UNHANDLED_EXCEPTION)
        );
        Test.stopTest();

        Assert.isTrue(jobA.hasFailed, 'Failure should be reconciled from the FinalizerContext.');
        Assert.isFalse(
            compensation.isProcessed,
            'Compensation runs because the reconciled outcome is FAILURE.'
        );
        Assert.isNotNull(compensation.salesforceJobId);
    }

    @IsTest
    private static void shouldStopChainSkippingRemainingJobs() {
        SuccessfulQueueableTest jobA = new SuccessfulQueueableTest();
        SuccessfulQueueableTest jobB = new SuccessfulQueueableTest();

        QueueableChain chain = new QueueableChain();
        chain.addJob(jobA);
        chain.addJob(jobB);
        QueueableManager.get().setChain(chain);

        Async.stopChain();

        Assert.isTrue(jobA.isProcessed);
        Assert.isTrue(jobB.isProcessed);
        Assert.isFalse(chain.hasNextJob(), 'No jobs remain after stopChain().');
    }

    @IsTest
    private static void shouldSkipJobByCustomJobId() {
        SuccessfulQueueableTest jobA = new SuccessfulQueueableTest();
        SuccessfulQueueableTest jobB = new SuccessfulQueueableTest();

        QueueableChain chain = new QueueableChain();
        chain.addJob(jobA);
        chain.addJob(jobB);
        QueueableManager.get().setChain(chain);

        Async.skipJob(jobB.customJobId);

        Assert.isFalse(jobA.isProcessed, 'Other jobs are untouched.');
        Assert.isTrue(jobB.isProcessed, 'The targeted job is skipped.');
    }

    @IsTest
    private static void shouldRejectSkipJobWithUnknownCustomJobId() {
        QueueableChain chain = new QueueableChain();
        chain.addJob(new SuccessfulQueueableTest());
        QueueableManager.get().setChain(chain);

        try {
            Async.skipJob('nope');
            Assert.fail('Should reject skipping an unknown custom job id.');
        } catch (Exception ex) {
            Assert.isTrue(ex.getMessage().contains('nope'));
        }
    }

    @IsTest
    private static void shouldStopChainFromAttachedFinalizer() {
        Test.startTest();
        Async.queueable(new ChainStoppingJob()).chain(new SuccessfulQueueableTest()).enqueue();
        Test.stopTest();

        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Account],
            'Downstream job is skipped after the finalizer stopped the chain.'
        );
    }

    private static Map<String, QueueableJobSetting__mdt> resultsEnabledForAll() {
        return new Map<String, QueueableJobSetting__mdt>{
            QueueableManager.QUEUEABLE_JOB_SETTING_ALL => new QueueableJobSetting__mdt(
                DeveloperName = QueueableManager.QUEUEABLE_JOB_SETTING_ALL,
                CreateResult__c = true
            )
        };
    }

    @IsTest
    private static void shouldCreateCompletedResultWithIdentityFields() {
        SuccessfulQueueableTest job = new SuccessfulQueueableTest();

        QueueableChain chain = new QueueableChain();
        chain.queueableJobSettingByJobName = resultsEnabledForAll();
        chain.addJob(job);
        QueueableManager.get().setChain(chain);

        Test.startTest();
        chain.executeCurrentJob(new AsyncMock.MockQueueableContext());
        chain.enqueueNextJobIfAnyFromFinalizer(
            new AsyncMock.MockFinalizerContext().setResult(ParentJobResult.SUCCESS)
        );
        Test.stopTest();

        AsyncResult__c result = [
            SELECT Status__c, ClassName__c, ChainId__c, RetryAttempts__c, Result__c
            FROM AsyncResult__c
            WHERE CustomJobId__c = :job.customJobId
        ];
        Assert.areEqual(QueueableManager.STATUS_COMPLETED, result.Status__c);
        Assert.isTrue(result.ClassName__c.contains('SuccessfulQueueableTest'));
        Assert.isNotNull(result.ChainId__c);
        Assert.areEqual(0, result.RetryAttempts__c);
        Assert.areEqual('SUCCESS', result.Result__c);
    }

    @IsTest
    private static void shouldCreateSkippedDependencyResultLinkedToBlocker() {
        FailureQueueableTest jobA = new FailureQueueableTest();
        jobA.continueOnJobExecuteFail = true;
        SuccessfulQueueableTest jobB = new SuccessfulQueueableTest();

        QueueableChain chain = new QueueableChain();
        chain.queueableJobSettingByJobName = resultsEnabledForAll();
        chain.addJob(jobA);
        jobB.dependencies = new List<Async.Dependency>{
            dependencyOn(jobA.customJobId, Async.Outcome.SUCCESS)
        };
        chain.addJob(jobB);
        QueueableManager.get().setChain(chain);

        Test.startTest();
        chain.executeCurrentJob(new AsyncMock.MockQueueableContext());
        chain.enqueueNextJobIfAnyFromFinalizer(
            new AsyncMock.MockFinalizerContext().setResult(ParentJobResult.UNHANDLED_EXCEPTION)
        );
        Test.stopTest();

        AsyncResult__c aResult = [
            SELECT Id, Status__c, ChainId__c, ExceptionType__c
            FROM AsyncResult__c
            WHERE CustomJobId__c = :jobA.customJobId
        ];
        AsyncResult__c bResult = [
            SELECT
                Status__c,
                SkipReason__c,
                DependsOnResult__c,
                RequiredOutcome__c,
                ActualOutcome__c,
                ChainId__c
            FROM AsyncResult__c
            WHERE CustomJobId__c = :jobB.customJobId
        ];

        Assert.areEqual(QueueableManager.STATUS_FAILED, aResult.Status__c);
        Assert.isNotNull(aResult.ExceptionType__c, 'Failed job records the exception type.');
        Assert.areEqual(QueueableManager.STATUS_SKIPPED_DEPENDENCY, bResult.Status__c);
        Assert.areEqual(
            aResult.Id,
            bResult.DependsOnResult__c,
            'B links to the result that blocked it.'
        );
        Assert.areEqual('SUCCESS', bResult.RequiredOutcome__c);
        Assert.areEqual('FAILURE', bResult.ActualOutcome__c);
        Assert.isNotNull(bResult.SkipReason__c);
        Assert.areEqual(aResult.ChainId__c, bResult.ChainId__c, 'Both rows share the chain id.');
    }

    @IsTest
    private static void shouldCreateDisabledSkipResult() {
        QueueableJobTest1 job = new QueueableJobTest1();

        QueueableChain chain = new QueueableChain();
        Map<String, QueueableJobSetting__mdt> settings = resultsEnabledForAll();
        settings.put(
            getClassNameWithNamespaceDotPrefix('AsyncTest.QueueableJobTest1'),
            new QueueableJobSetting__mdt(
                DeveloperName = getClassNameWithNamespaceDotPrefix('AsyncTest.QueueableJobTest1'),
                IsDisabled__c = true
            )
        );
        chain.queueableJobSettingByJobName = settings;
        chain.addJob(job);

        Test.startTest();
        chain.removeJobsThatAreDisabledAndDependentFinalizers();
        Test.stopTest();

        AsyncResult__c result = [
            SELECT Status__c, SkipReason__c
            FROM AsyncResult__c
            WHERE CustomJobId__c = :job.customJobId
        ];
        Assert.areEqual(QueueableManager.STATUS_SKIPPED_DISABLED, result.Status__c);
        Assert.isNotNull(result.SkipReason__c);
    }

    private static MarkerJob markerJob(String tag, Boolean shouldFail) {
        MarkerJob job = new MarkerJob();
        job.tag = tag;
        job.shouldFail = shouldFail;
        return job;
    }

    private static Integer accountCount(String name) {
        return [SELECT COUNT() FROM Account WHERE Name = :name];
    }

    @IsTest
    private static void shouldGateChainOnDependencyOutcomesEndToEnd() {
        Test.startTest();
        Async.Result a = Async.queueable(markerJob('A', true)).continueOnJobExecuteFail().chain();
        Async.queueable(markerJob('B', false)).dependsOn(Async.after(a).succeeded()).chain();
        Async.queueable(markerJob('C', false)).dependsOn(Async.after(a).failed()).enqueue();
        Test.stopTest();

        Assert.areEqual(1, accountCount('A'), 'A ran (and committed despite failing).');
        Assert.areEqual(0, accountCount('B'), 'B is skipped: it needs A to succeed, but A failed.');
        Assert.areEqual(1, accountCount('C'), 'C runs: it is the compensation for A failing.');
    }

    @IsTest
    private static void shouldRecordChainResultsEndToEnd() {
        QueueableChain chain = new QueueableChain();
        chain.queueableJobSettingByJobName = resultsEnabledForAll();
        QueueableManager.get().setChain(chain);

        Test.startTest();
        Async.Result a = Async.queueable(markerJob('A', true)).continueOnJobExecuteFail().chain();
        Async.queueable(markerJob('B', false)).dependsOn(Async.after(a).succeeded()).chain();
        Async.queueable(markerJob('C', false)).dependsOn(Async.after(a).failed()).enqueue();
        Test.stopTest();

        Map<String, AsyncResult__c> byStatus = new Map<String, AsyncResult__c>();
        Set<String> chainIds = new Set<String>();
        for (AsyncResult__c result : [
            SELECT
                Status__c,
                ChainId__c,
                DependsOnResult__c,
                ExceptionType__c,
                RequiredOutcome__c,
                ActualOutcome__c
            FROM AsyncResult__c
        ]) {
            byStatus.put(result.Status__c, result);
            chainIds.add(result.ChainId__c);
        }

        Assert.areEqual(3, byStatus.size(), 'One result row per job (ran and skipped).');
        Assert.areEqual(1, chainIds.size(), 'All rows share one ChainId.');

        AsyncResult__c failed = byStatus.get(QueueableManager.STATUS_FAILED);
        AsyncResult__c skipped = byStatus.get(QueueableManager.STATUS_SKIPPED_DEPENDENCY);
        Assert.isNotNull(byStatus.get(QueueableManager.STATUS_COMPLETED), 'C completed.');
        Assert.isNotNull(failed.ExceptionType__c, 'Failed row captures the exception type.');
        Assert.areEqual(
            failed.Id,
            skipped.DependsOnResult__c,
            'Skipped B links to the result that blocked it (A).'
        );
        Assert.areEqual('SUCCESS', skipped.RequiredOutcome__c);
        Assert.areEqual('FAILURE', skipped.ActualOutcome__c);
    }

    @IsTest
    private static void shouldRunLinearDependencyChainEndToEnd() {
        Test.startTest();
        Async.queueable(markerJob('X', false))
            .chain(markerJob('Y', false))
            .dependsOn(Async.afterPrevious().succeeded())
            .chain(markerJob('Z', false))
            .dependsOn(Async.afterPrevious().succeeded())
            .enqueue();
        Test.stopTest();

        Assert.areEqual(1, accountCount('X'));
        Assert.areEqual(1, accountCount('Y'), 'Y runs after X succeeds.');
        Assert.areEqual(1, accountCount('Z'), 'Z runs after Y succeeds.');
    }

    @IsTest
    private static void shouldSkipDownstreamWhenLinearDependencyFailsEndToEnd() {
        Test.startTest();
        Async.queueable(markerJob('X', true))
            .continueOnJobExecuteFail()
            .chain(markerJob('Y', false))
            .dependsOn(Async.afterPrevious().succeeded())
            .chain(markerJob('Z', false))
            .dependsOn(Async.afterPrevious().succeeded())
            .enqueue();
        Test.stopTest();

        Assert.areEqual(1, accountCount('X'), 'X ran (committed despite failing).');
        Assert.areEqual(0, accountCount('Y'), 'Y skipped: X failed.');
        Assert.areEqual(0, accountCount('Z'), 'Z skipped transitively: Y never ran.');
    }

    @IsTest
    private static void shouldRecordRetryHistoryOnExhaustionEndToEnd() {
        QueueableChain chain = new QueueableChain();
        chain.queueableJobSettingByJobName = resultsEnabledForAll();
        QueueableManager.get().setChain(chain);

        Test.startTest();
        Async.queueable(markerJob('R', true)).continueOnJobExecuteFail().retry(2).enqueue();
        Test.stopTest();

        Assert.areEqual(3, accountCount('R'), 'Original run plus 2 retries each execute work().');

        AsyncResult__c result = [
            SELECT Status__c, RetryAttempts__c, RetryHistory__c
            FROM AsyncResult__c
        ];
        Assert.areEqual(
            QueueableManager.STATUS_FAILED,
            result.Status__c,
            'Only the final, exhausted attempt produces a result row.'
        );
        Assert.areEqual(2, result.RetryAttempts__c);
        Assert.isTrue(String.isNotBlank(result.RetryHistory__c), 'Retry history is recorded.');
    }

    @IsTest
    private static void shouldRunConsumerFinalizerOnceWhenRetriesAreExhausted() {
        Test.startTest();
        Async.queueable(new FinalizerAttachingRetryJob())
            .continueOnJobExecuteFail()
            .retry(2)
            .enqueue();
        Test.stopTest();

        Assert.areEqual(
            3,
            accountCount('RETRY-PARENT'),
            'Original run plus 2 retries each execute work().'
        );
        Assert.areEqual(
            1,
            accountCount('RETRY-FINALIZER'),
            'Re-attaching on every attempt must not queue one finalizer per attempt.'
        );
    }

    @IsTest
    private static void shouldChainFollowUpJobOnceWhenRetriesAreExhausted() {
        Test.startTest();
        Async.queueable(new JobChainingRetryJob()).continueOnJobExecuteFail().retry(2).enqueue();
        Test.stopTest();

        Assert.areEqual(
            3,
            accountCount('CHAIN-PARENT'),
            'Original run plus 2 retries each execute work().'
        );
        Assert.areEqual(
            1,
            accountCount('CHAIN-FOLLOWUP'),
            'Re-chaining on every attempt must not queue one follow-up per attempt.'
        );
    }

    @IsTest
    private static void shouldKeepEveryAttemptInRetryHistoryAfterDiscardingChainChanges() {
        QueueableChain chain = new QueueableChain();
        chain.queueableJobSettingByJobName = resultsEnabledForAll();
        QueueableManager.get().setChain(chain);

        Test.startTest();
        Async.queueable(new FinalizerAttachingRetryJob())
            .continueOnJobExecuteFail()
            .retry(2)
            .enqueue();
        Test.stopTest();

        AsyncResult__c result = [
            SELECT Status__c, RetryAttempts__c, RetryHistory__c, ExceptionMessage__c
            FROM AsyncResult__c
            WHERE ClassName__c LIKE '%FinalizerAttachingRetryJob'
        ];
        Assert.areEqual(QueueableManager.STATUS_FAILED, result.Status__c);
        Assert.areEqual(2, result.RetryAttempts__c, 'Every attempt is still counted.');
        Assert.areEqual(CUSTOM_ERROR_MESSAGE, result.ExceptionMessage__c);
        for (String attempt : new List<String>{ 'Attempt 1', 'Attempt 2', 'Attempt 3' }) {
            Assert.isTrue(
                result.RetryHistory__c.contains(attempt),
                'Discarding a failed attempt must not lose ' + attempt + ' from the history.'
            );
        }
    }

    @IsTest
    private static void shouldReportNoRetryConfiguredWhenJobHasNoRetryPolicy() {
        Test.startTest();
        Async.queueable(new FailureHookJob()).continueOnJobExecuteFail().enqueue();
        Test.stopTest();

        Assert.areEqual(
            'NOT_CONFIGURED|HAS-TRACE|0/0',
            hookRecord().Description,
            'A job with no retry policy did not stop because of a retry decision.'
        );
    }

    @IsTest
    private static void shouldReportRetriesExhaustedAndFireOnlyOnce() {
        Test.startTest();
        Async.queueable(new FailureHookJob()).continueOnJobExecuteFail().retry(2).enqueue();
        Test.stopTest();

        Assert.areEqual(1, accountCount('HOOK'), 'The hook fires once, after the last attempt.');
        Assert.areEqual('EXHAUSTED|HAS-TRACE|2/2', hookRecord().Description);
    }

    @IsTest
    private static void shouldReportNotRetryableWhenExceptionTypeIsExcluded() {
        Test.startTest();
        Async.queueable(new FailureHookJob())
            .continueOnJobExecuteFail()
            .retry(2)
            .retryOn(System.DmlException.class)
            .enqueue();
        Test.stopTest();

        Assert.areEqual(
            'NOT_RETRYABLE|HAS-TRACE|0/2',
            hookRecord().Description,
            'The retryOn filter rejected the type, so no attempt was ever retried.'
        );
    }

    @IsTest
    private static void shouldNotCallOnFinalFailureWhenJobSucceeds() {
        Test.startTest();
        Async.queueable(new SucceedingHookJob()).enqueue();
        Test.stopTest();

        Assert.areEqual(0, accountCount('HOOK'), 'A job that succeeded never failed finally.');
    }

    @IsTest
    private static void shouldNotCallOnFinalFailureWhenJobIsSkipped() {
        Test.startTest();
        Async.Result gate = Async.queueable(markerJob('GATE', true))
            .continueOnJobExecuteFail()
            .chain();
        Async.queueable(new FailureHookJob()).dependsOn(Async.after(gate).succeeded()).enqueue();
        Test.stopTest();

        Assert.areEqual(0, accountCount('HOOK'), 'A skipped job never ran, so it never failed.');
    }

    @IsTest
    private static void shouldKeepChainRunningWhenOnFinalFailureThrows() {
        QueueableChain chain = new QueueableChain();
        chain.queueableJobSettingByJobName = resultsEnabledForAll();
        QueueableManager.get().setChain(chain);

        Test.startTest();
        Async.queueable(new ExplodingHookJob()).continueOnJobExecuteFail().chain();
        Async.queueable(markerJob('AFTER-HOOK', false)).enqueue();
        Test.stopTest();

        Assert.areEqual(1, accountCount('AFTER-HOOK'), 'A throwing hook must not stop the chain.');

        AsyncResult__c result = [
            SELECT RetryHistory__c
            FROM AsyncResult__c
            WHERE ClassName__c LIKE '%ExplodingHookJob'
        ];
        Assert.isTrue(
            result.RetryHistory__c.contains('onFinalFailure() override threw'),
            'A throwing hook is recorded instead of being swallowed silently.'
        );
    }

    @IsTest
    private static void shouldCallOnFinalFailureForEveryFailedChunkPage() {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 4; i++) {
            accounts.add(new Account(Name = 'Chunk Hook ' + i));
        }
        insert accounts;

        Test.startTest();
        Async.chunk(new FailingChunkHookJob(), ChunkSource.of(accounts)).chunkSize(2).enqueue();
        Test.stopTest();

        Assert.areEqual(2, accountCount('HOOK'), 'Each failed page is its own final failure.');
    }

    private static Account hookRecord() {
        return [SELECT Description FROM Account WHERE Name = 'HOOK' LIMIT 1];
    }

    private static String getClassNameWithNamespaceDotPrefix(String className) {
        return getNamespaceDotPrefix() + className;
    }

    private static String getNamespaceDotPrefix() {
        String className = AsyncTest.class.getName();
        return className.contains('.') ? className.substringBefore('.') + '.' : '';
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

    @IsTest
    private static void shouldOrderFinalizerBeforeRegularJob() {
        QueueableJobTest1 finalizerJob = new QueueableJobTest1();
        finalizerJob.parentCustomJobId = 'parent';
        QueueableJobTest1 regularJob = new QueueableJobTest1();

        Assert.areEqual(-1, finalizerJob.compareTo(regularJob), 'Finalizer sorts first.');
        Assert.areEqual(
            1,
            regularJob.compareTo(finalizerJob),
            'Regular job sorts after finalizer.'
        );
    }

    @IsTest
    private static void shouldNotMatchBlankExceptionType() {
        QueueableJobTest1 job = new QueueableJobTest1();

        Assert.isFalse(job.matchesRetryOnTypes(null), 'A null type name never matches.');
        Assert.isFalse(job.matchesRetryOnTypes(''), 'A blank type name never matches.');
    }

    @IsTest
    private static void shouldExposeQueueableJobContextAccessors() {
        QueueableJobTest1 job = new QueueableJobTest1();
        job.queueableCtx = new AsyncMock.MockQueueableContext();

        Async.QueueableJobContext ctx = new Async.QueueableJobContext();
        ctx.currentJob = job;

        Assert.areEqual(job.queueableCtx, ctx.queueableCtx, 'Exposes the job queueable context.');
        Assert.isNull(ctx.finalizerCtx, 'Finalizer context is null when none was attached.');
    }

    @IsTest
    private static void shouldBuildFinishedDependency() {
        Async.Dependency dependency = Async.afterPrevious().finished();

        Assert.areEqual(
            Async.Outcome.COMPLETED,
            dependency.requiredOutcome,
            'finished() requires the COMPLETED outcome.'
        );
    }

    @IsTest
    private static void shouldSetBackoffViaBuilder() {
        Test.startTest();
        Async.Result result = Async.queueable(new QueueableJobTest1())
            .retry(2)
            .backoff(Backoff.fixed(5))
            .enqueue();
        Test.stopTest();

        Assert.isNotNull(result.job.backoff, 'backoff() registers a policy on the job.');
        Assert.areEqual(5, result.job.backoff.delayMinutes(1));
    }

    @IsTest
    private static void shouldRejectNullChain() {
        try {
            QueueableManager.get().setChain(null);
            Assert.fail('Should reject a null chain.');
        } catch (Exception ex) {
            Assert.isNotNull(ex.getMessage());
        }
    }

    @IsTest
    private static void shouldRejectNullFinalizerJob() {
        try {
            QueueableManager.get().attachFinalizer(null);
            Assert.fail('Should reject a null finalizer job.');
        } catch (Exception ex) {
            Assert.isNotNull(ex.getMessage());
        }
    }

    @IsTest
    private static void shouldRejectNullChainedJob() {
        try {
            QueueableManager.get().chain(null);
            Assert.fail('Should reject a null chained job.');
        } catch (Exception ex) {
            Assert.isNotNull(ex.getMessage());
        }
    }

    @IsTest
    private static void shouldReturnEarlyWhenChainHasNoJobs() {
        QueueableChain chain = new QueueableChain();
        QueueableManager.get().setChain(chain);

        chain.executeCurrentJob(new AsyncMock.MockQueueableContext());

        Assert.areEqual(0, chain.jobs.size(), 'An empty chain has nothing to execute.');
    }

    @IsTest
    private static void shouldApplyCmdtRetryWithBlankExceptionList() {
        QueueableJobTest1 job = new QueueableJobTest1();

        QueueableChain chain = new QueueableChain();
        chain.queueableJobSettingByJobName = new Map<String, QueueableJobSetting__mdt>{
            QueueableManager.QUEUEABLE_JOB_SETTING_ALL => new QueueableJobSetting__mdt(
                DeveloperName = QueueableManager.QUEUEABLE_JOB_SETTING_ALL,
                MaxRetries__c = 2,
                RetryableExceptions__c = '   '
            )
        };
        chain.addJob(job);

        Assert.areEqual(2, job.maxRetries);
        Assert.isNull(
            job.retryOnExceptionTypes,
            'A blank CMDT exception list leaves no type filter.'
        );
    }

    @IsTest
    private static void shouldLabelSkipReasonWithRawIdWhenTargetNotInChain() {
        SuccessfulQueueableTest jobA = new SuccessfulQueueableTest();
        SuccessfulQueueableTest jobB = new SuccessfulQueueableTest();
        jobB.dependencies = new List<Async.Dependency>{
            dependencyOn('ghost-custom-job-id', Async.Outcome.SUCCESS)
        };

        QueueableChain chain = new QueueableChain();
        chain.addJob(jobA);
        chain.addJob(jobB);
        QueueableManager.get().setChain(chain);

        Test.startTest();
        chain.executeCurrentJob(new AsyncMock.MockQueueableContext());
        chain.enqueueNextJobIfAnyFromFinalizer(
            new AsyncMock.MockFinalizerContext().setResult(ParentJobResult.SUCCESS)
        );
        Test.stopTest();

        Assert.isTrue(jobB.isProcessed, 'A job depending on an unknown id is skipped.');
        Assert.isTrue(
            jobB.skipReason.contains('ghost-custom-job-id'),
            'An unresolved target falls back to its raw custom job id.'
        );
    }

    @IsTest
    private static void shouldThrowWhenDeepCloneClassCannotBeResolved() {
        DeepCloneFailJob job = new DeepCloneFailJob();
        job.deepClone = true;

        try {
            job.cloneJob();
            Assert.fail('A failed deep clone must surface a helpful error.');
        } catch (Exception ex) {
            Assert.isTrue(ex.getMessage().contains('deepClone'));
        }
    }

    @IsTest
    private static void shouldDeepCloneJobWithDottedClassName() {
        QueueableJobTest1 job = new QueueableJobTest1();
        job.deepClone = true;

        try {
            Assert.isNotNull(job.cloneJob());
        } catch (Exception ex) {
            Assert.isTrue(ex.getMessage().contains('deepClone'));
        }
    }

    @IsTest
    private static void shouldCacheClassNamePerInstanceWithoutCrossContamination() {
        SuccessfulQueueableTest jobA = new SuccessfulQueueableTest();
        FailureQueueableTest jobB = new FailureQueueableTest();

        String jobAClassName = jobA.className;
        String jobBClassName = jobB.className;

        Assert.areEqual(
            getClassNameWithNamespaceDotPrefix('AsyncTest.SuccessfulQueueableTest'),
            jobAClassName
        );
        Assert.areEqual(
            getClassNameWithNamespaceDotPrefix('AsyncTest.FailureQueueableTest'),
            jobBClassName
        );
        Assert.areEqual(jobAClassName, jobA.className, 'Repeated access returns the same name.');
        Assert.areEqual(
            jobAClassName,
            jobA.cloneJob().className,
            'A shallow clone reports its own class name.'
        );

        SuccessfulQueueableTest roundTripped = (SuccessfulQueueableTest) JSON.deserialize(
            JSON.serialize(jobA),
            SuccessfulQueueableTest.class
        );
        Assert.areEqual(
            jobAClassName,
            roundTripped.className,
            'A JSON round trip recomputes the name from the runtime type.'
        );
    }

    @IsTest
    private static void shouldDeleteOnlyOldFailedResultsWhenOnlyFailedRetentionIsSet() {
        List<AsyncResult__c> oldFailedResults = new List<AsyncResult__c>();
        for (Integer i = 0; i < 200; i++) {
            oldFailedResults.add(new AsyncResult__c(Status__c = QueueableManager.STATUS_FAILED));
        }
        insert oldFailedResults;
        for (AsyncResult__c result : oldFailedResults) {
            Test.setCreatedDate(result.Id, System.now().addDays(-31));
        }
        AsyncResult__c recentFailed = insertAsyncResultWithAge(QueueableManager.STATUS_FAILED, 5);
        AsyncResult__c veryOldCompleted = insertAsyncResultWithAge(
            QueueableManager.STATUS_COMPLETED,
            400
        );

        Test.startTest();
        Async.batchable(new AsyncResultCleanupBatch().failedOlderThanDays(30)).execute();
        Test.stopTest();

        Set<Id> remainingIds = new Map<Id, AsyncResult__c>([SELECT Id FROM AsyncResult__c])
            .keySet();
        Assert.areEqual(2, remainingIds.size(), 'Only the two out-of-track results survive.');
        Assert.isTrue(remainingIds.contains(recentFailed.Id), 'Recent failed results survive.');
        Assert.isTrue(
            remainingIds.contains(veryOldCompleted.Id),
            'Non-failed results are untouched when their track has no retention.'
        );
    }

    @IsTest
    private static void shouldDeleteOnlyOldNonFailedResultsWhenOnlyOthersRetentionIsSet() {
        insertAsyncResultWithAge(QueueableManager.STATUS_COMPLETED, 31);
        insertAsyncResultWithAge(QueueableManager.STATUS_SKIPPED_DEPENDENCY, 31);
        AsyncResult__c veryOldFailed = insertAsyncResultWithAge(
            QueueableManager.STATUS_FAILED,
            400
        );
        AsyncResult__c recentCompleted = insertAsyncResultWithAge(
            QueueableManager.STATUS_COMPLETED,
            5
        );

        Test.startTest();
        Async.batchable(new AsyncResultCleanupBatch().othersOlderThanDays(30)).execute();
        Test.stopTest();

        Set<Id> remainingIds = new Map<Id, AsyncResult__c>([SELECT Id FROM AsyncResult__c])
            .keySet();
        Assert.areEqual(2, remainingIds.size(), 'Old completed and skipped results are deleted.');
        Assert.isTrue(
            remainingIds.contains(veryOldFailed.Id),
            'Failed results are untouched when their track has no retention.'
        );
        Assert.isTrue(
            remainingIds.contains(recentCompleted.Id),
            'Recent non-failed results survive.'
        );
    }

    @IsTest
    private static void shouldApplySeparateRetentionCutoffsPerTrack() {
        insertAsyncResultWithAge(QueueableManager.STATUS_FAILED, 100);
        AsyncResult__c failedWithinCutoff = insertAsyncResultWithAge(
            QueueableManager.STATUS_FAILED,
            60
        );
        insertAsyncResultWithAge(QueueableManager.STATUS_COMPLETED, 60);
        AsyncResult__c completedWithinCutoff = insertAsyncResultWithAge(
            QueueableManager.STATUS_COMPLETED,
            10
        );

        Test.startTest();
        Async.batchable(
                new AsyncResultCleanupBatch().failedOlderThanDays(90).othersOlderThanDays(30)
            )
            .execute();
        Test.stopTest();

        Set<Id> remainingIds = new Map<Id, AsyncResult__c>([SELECT Id FROM AsyncResult__c])
            .keySet();
        Assert.areEqual(2, remainingIds.size(), 'Each track applies its own cutoff.');
        Assert.isTrue(
            remainingIds.contains(failedWithinCutoff.Id),
            'A failed result younger than the failed retention survives.'
        );
        Assert.isTrue(
            remainingIds.contains(completedWithinCutoff.Id),
            'A non-failed result younger than the others retention survives.'
        );
    }

    @IsTest
    private static void shouldThrowWhenNoRetentionTrackIsConfigured() {
        try {
            new AsyncResultCleanupBatch().start(null);
            Assert.fail('Running the cleanup with no retention configured must throw.');
        } catch (IllegalArgumentException ex) {
            Assert.areEqual(
                AsyncResultCleanupBatch.ERROR_MESSAGE_NO_RETENTION_CONFIGURED,
                ex.getMessage()
            );
        }
    }

    @IsTest
    private static void shouldRejectNonPositiveRetentionDays() {
        try {
            new AsyncResultCleanupBatch().failedOlderThanDays(0);
            Assert.fail('Zero retention days must be rejected.');
        } catch (IllegalArgumentException ex) {
            Assert.areEqual(
                AsyncResultCleanupBatch.ERROR_MESSAGE_INVALID_RETENTION_DAYS,
                ex.getMessage()
            );
        }

        try {
            new AsyncResultCleanupBatch().othersOlderThanDays(null);
            Assert.fail('Null retention days must be rejected.');
        } catch (IllegalArgumentException ex) {
            Assert.areEqual(
                AsyncResultCleanupBatch.ERROR_MESSAGE_INVALID_RETENTION_DAYS,
                ex.getMessage()
            );
        }
    }

    private static AsyncResult__c insertAsyncResultWithAge(String status, Integer ageDays) {
        AsyncResult__c result = new AsyncResult__c(Status__c = status);
        insert result;
        Test.setCreatedDate(result.Id, System.now().addDays(-ageDays));
        return result;
    }

    private class DeepCloneFailJob extends QueueableJob {
        public override void work() {
        }
        public override QueueableJob cloneForDeepCopy() {
            throw new JSONException('forced deep clone failure');
        }
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

    private class ChainStoppingJob extends QueueableJob {
        public override void work() {
            Async.queueable(new StopChainFinalizer()).attachFinalizer();
        }
    }

    private class MarkerJob extends QueueableJob {
        public String tag;
        public Boolean shouldFail = false;
        public override void work() {
            insert new Account(Name = tag);
            if (shouldFail) {
                throw new CustomException(AsyncTest.CUSTOM_ERROR_MESSAGE);
            }
        }
    }

    private class StopChainFinalizer extends QueueableJob.Finalizer {
        public override void work() {
            Async.stopChain();
        }
    }

    private class FinalizerAttachingRetryJob extends QueueableJob {
        public override void work() {
            insert new Account(Name = 'RETRY-PARENT');
            Async.queueable(new MarkerFinalizer()).attachFinalizer();
            throw new CustomException(AsyncTest.CUSTOM_ERROR_MESSAGE);
        }
    }

    private class MarkerFinalizer extends QueueableJob.Finalizer {
        public override void work() {
            insert new Account(Name = 'RETRY-FINALIZER');
        }
    }

    private abstract class HookRecordingJob extends QueueableJob {
        public override void onFinalFailure(Async.FailureContext failureCtx) {
            insert new Account(
                Name = 'HOOK',
                Description = failureCtx.retryOutcome.name() +
                    '|' +
                    (String.isBlank(failureCtx.failure?.stackTrace) ? 'NO-TRACE' : 'HAS-TRACE') +
                    '|' +
                    failureCtx.retryAttempt +
                    '/' +
                    failureCtx.maxRetries
            );
        }
    }

    private class FailureHookJob extends HookRecordingJob {
        public override void work() {
            throw new CustomException(AsyncTest.CUSTOM_ERROR_MESSAGE);
        }
    }

    private class SucceedingHookJob extends HookRecordingJob {
        public override void work() {
            insert new Account(Name = 'SUCCEEDED');
        }
    }

    private class ExplodingHookJob extends QueueableJob {
        public override void work() {
            throw new CustomException(AsyncTest.CUSTOM_ERROR_MESSAGE);
        }

        public override void onFinalFailure(Async.FailureContext failureCtx) {
            throw new CustomException('hook exploded');
        }
    }

    private class FailingChunkHookJob extends ChunkJob {
        public override void work(List<SObject> chunk) {
            throw new CustomException(AsyncTest.CUSTOM_ERROR_MESSAGE);
        }

        public override void onFinalFailure(Async.FailureContext failureCtx) {
            insert new Account(Name = 'HOOK', Description = failureCtx.retryOutcome.name());
        }
    }

    private class JobChainingRetryJob extends QueueableJob {
        public override void work() {
            insert new Account(Name = 'CHAIN-PARENT');
            Async.queueable(markerJob('CHAIN-FOLLOWUP', false)).chain();
            throw new CustomException(AsyncTest.CUSTOM_ERROR_MESSAGE);
        }
    }

    private class NonRetryableJob extends QueueableJob {
        public override void work() {
        }
        public override Boolean isRetryable(Exception ex) {
            return false;
        }
    }

    private class MessageVetoJob extends QueueableJob {
        public override void work() {
        }
        public override Boolean isRetryable(Exception ex) {
            return !ex.getMessage().containsIgnoreCase('permanent');
        }
    }

    private class ThrowingClassifierJob extends QueueableJob {
        public override void work() {
        }
        public override Boolean isRetryable(Exception ex) {
            throw new CustomException('classifier blew up');
        }
    }

    private class ResettableRetryJob extends QueueableJob {
        public Boolean wasReset = false;
        public override void work() {
            throw new CustomException(AsyncTest.CUSTOM_ERROR_MESSAGE);
        }
        public override void resetForRetry() {
            this.wasReset = true;
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

    @IsTest
    private static void shouldProcessFirstChunkThroughEnqueue() {
        List<Account> accounts = createAccounts(5);

        Test.startTest();
        Async.Result result = Async.chunk(new MarkingChunkJob(), ChunkSource.of(accounts))
            .chunkSize(5)
            .enqueue();
        Test.stopTest();

        Assert.areNotEqual(null, result.salesforceJobId);
        Assert.areEqual(
            5,
            [SELECT COUNT() FROM Account WHERE Site = :CHUNK_PROCESSED],
            'The single chunk should process every record in the source.'
        );
    }

    @IsTest
    private static void shouldProcessAllInMemoryChunksAcrossPages() {
        List<Account> accounts = createAccounts(6);

        Test.startTest();
        Async.chunk(new MarkingChunkJob(), ChunkSource.of(accounts)).chunkSize(3).enqueue();
        Test.stopTest();

        Assert.areEqual(
            6,
            [SELECT COUNT() FROM Account WHERE Site = :CHUNK_PROCESSED],
            'Self-chaining must process every page of the run.'
        );
    }

    @IsTest
    private static void shouldProcessAllCursorChunksAcrossPages() {
        createAccounts(6);

        Test.startTest();
        Async.chunk(new MarkingChunkJob(), ChunkSource.query('SELECT Id FROM Account'))
            .chunkSize(3)
            .enqueue();
        Test.stopTest();

        Assert.areEqual(
            6,
            [SELECT COUNT() FROM Account WHERE Site = :CHUNK_PROCESSED],
            'A cursor must survive re-enqueue and fetch every page.'
        );
    }

    @IsTest
    private static void shouldCarryJobMemberStateAcrossChunks() {
        List<Account> accounts = createAccounts(6);

        Test.startTest();
        Async.chunk(new LabelingChunkJob('RUN_LABEL'), ChunkSource.of(accounts))
            .chunkSize(2)
            .enqueue();
        Test.stopTest();

        Assert.areEqual(
            6,
            [SELECT COUNT() FROM Account WHERE Site = 'RUN_LABEL'],
            'Job member state must survive cloning and serialization across every page.'
        );
    }

    @IsTest
    private static void shouldContinueToNextChunkAfterAFailedChunk() {
        List<Account> accounts = accountsWithOneFailingRecord();

        Test.startTest();
        Async.chunk(new FailMarkedChunkJob(), ChunkSource.of(accounts)).chunkSize(2).enqueue();
        Test.stopTest();

        Assert.areEqual(
            4,
            [SELECT COUNT() FROM Account WHERE Site = :CHUNK_PROCESSED],
            'A failed chunk must not stop the remaining chunks by default.'
        );
    }

    @IsTest
    private static void shouldStopAfterFailedChunkWhenConfigured() {
        List<Account> accounts = new List<Account>{
            new Account(Name = 'FAIL first'),
            new Account(Name = 'ok second'),
            new Account(Name = 'ok third'),
            new Account(Name = 'ok fourth')
        };
        insert accounts;

        Test.startTest();
        Async.chunk(new FailMarkedChunkJob(), ChunkSource.of(accounts))
            .chunkSize(2)
            .stopRemainingChunksOnFailure()
            .enqueue();
        Test.stopTest();

        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Account WHERE Site = :CHUNK_PROCESSED],
            'stopRemainingChunksOnFailure must halt the run after a failed chunk.'
        );
    }

    @IsTest
    private static void shouldApplyAllChunkBuilderOptions() {
        List<Account> accounts = createAccounts(2);

        Test.startTest();
        Async.Result result = Async.chunk(new MarkingChunkJob(), ChunkSource.of(accounts))
            .chunkSize(2)
            .priority(3)
            .delay(1)
            .delayBetweenChunks(1)
            .retry(2)
            .backoff(Backoff.fixed(1))
            .retryOn(CustomException.class)
            .mockId('chunk-mock')
            .keepChunkPages()
            .stopRemainingChunksOnFailure()
            .enqueue();
        Test.stopTest();

        Assert.areNotEqual(
            null,
            result.salesforceJobId,
            'Every builder option should still enqueue.'
        );
    }

    @IsTest
    private static void shouldProcessFirstChunkInBulk() {
        List<Account> accounts = createAccounts(200);

        Test.startTest();
        Async.chunk(new MarkingChunkJob(), ChunkSource.of(accounts)).chunkSize(200).enqueue();
        Test.stopTest();

        Assert.areEqual(
            200,
            [SELECT COUNT() FROM Account WHERE Site = :CHUNK_PROCESSED],
            'A 200-record chunk should process in one bulk-safe page.'
        );
    }

    @IsTest
    private static void shouldFetchCorrectOffsetForLaterChunk() {
        List<Account> accounts = createAccounts(10);
        MarkingChunkJob job = new MarkingChunkJob();
        job.getRun().configure(ChunkSource.of(accounts), 5, false, null, false);
        job.getRun().position = 5;

        job.work();

        Set<Id> laterHalf = new Set<Id>();
        for (Integer i = 5; i < 10; i++) {
            laterHalf.add(accounts[i].Id);
        }
        List<Account> processed = [SELECT Id FROM Account WHERE Site = :CHUNK_PROCESSED];
        Assert.areEqual(
            5,
            processed.size(),
            'Only the second page of records should be processed.'
        );
        for (Account processedAccount : processed) {
            Assert.isTrue(
                laterHalf.contains(processedAccount.Id),
                'Offset fetch must return records from position 5 onward.'
            );
        }
    }

    @IsTest
    private static void shouldRejectChunkJobRunningOutsideAChunkRun() {
        try {
            new MarkingChunkJob().work();
            Assert.fail('A ChunkJob without a configured run must not execute.');
        } catch (IllegalArgumentException ex) {
            Assert.areEqual(ChunkRun.ERROR_MESSAGE_RUN_NOT_STARTED, ex.getMessage());
        }
    }

    @IsTest
    private static void shouldCreateResultRowForChunk() {
        List<Account> accounts = createAccounts(3);
        QueueableChain chain = new QueueableChain();
        chain.queueableJobSettingByJobName = resultsEnabledForAll();

        Test.startTest();
        QueueableManager.get().setChain(chain);
        Async.chunk(new MarkingChunkJob(), ChunkSource.of(accounts)).chunkSize(3).enqueue();
        Test.stopTest();

        List<AsyncResult__c> results = [
            SELECT Id, Status__c, ChainId__c, ClassName__c
            FROM AsyncResult__c
        ];
        Assert.areEqual(1, results.size(), 'A completed chunk page should record one AsyncResult.');
        Assert.areEqual(QueueableManager.STATUS_COMPLETED, results[0].Status__c);
        Assert.areNotEqual(null, results[0].ChainId__c);
    }

    @IsTest
    private static void shouldReturnNextChunkWhenRecordsRemain() {
        MarkingChunkJob job = new MarkingChunkJob();
        job.getRun().configure(ChunkSource.of(createAccounts(10)), 5, false, null, false);

        ChunkJob nextPage = job.nextPageOrNull();

        Assert.areNotEqual(null, nextPage, 'A next page is expected while records remain.');
        Assert.areEqual(5, nextPage.getRun().position, 'The next page must advance by chunkSize.');
    }

    @IsTest
    private static void shouldNotCarryInitialDelayToLaterChunks() {
        MarkingChunkJob job = new MarkingChunkJob();
        job.getRun().configure(ChunkSource.of(createAccounts(10)), 5, false, null, false);
        job.delay = 5;

        ChunkJob nextPage = job.nextPageOrNull();

        Assert.areEqual(null, nextPage.delay, 'An initial delay must not repeat on every page.');
    }

    @IsTest
    private static void shouldApplyDelayBetweenChunks() {
        MarkingChunkJob job = new MarkingChunkJob();
        job.getRun().configure(ChunkSource.of(createAccounts(10)), 5, false, 3, false);

        ChunkJob nextPage = job.nextPageOrNull();

        Assert.areEqual(3, nextPage.delay, 'delayBetweenChunks must throttle each later page.');
    }

    @IsTest
    private static void shouldRejectDeepCloneChunkJob() {
        MarkingChunkJob job = new MarkingChunkJob();
        job.deepClone = true;

        try {
            Async.chunk(job, ChunkSource.of(createAccounts(2)));
            Assert.fail('A deepClone ChunkJob should be rejected at build time.');
        } catch (Exception ex) {
            Assert.areEqual(ChunkBuilder.ERROR_MESSAGE_DEEP_CLONE_UNSUPPORTED, ex.getMessage());
        }
    }

    @IsTest
    private static void shouldPruneSettledPagesByDefault() {
        MarkingChunkJob job = new MarkingChunkJob();
        job.getRun().configure(ChunkSource.of(createAccounts(4)), 2, false, null, false);

        Assert.isFalse(job.getRun().keepPages, 'Settled pages are pruned by default.');
    }

    @IsTest
    private static void shouldKeepSettledPagesWhenRequested() {
        List<Account> accounts = createAccounts(6);

        Test.startTest();
        Async.chunk(new MarkingChunkJob(), ChunkSource.of(accounts))
            .chunkSize(2)
            .keepChunkPages()
            .enqueue();
        Test.stopTest();

        Assert.areEqual(
            6,
            [SELECT COUNT() FROM Account WHERE Site = :CHUNK_PROCESSED],
            'A kept-pages run still processes every page.'
        );
    }

    @IsTest
    private static void shouldReturnNoNextChunkAtEndOfSource() {
        MarkingChunkJob job = new MarkingChunkJob();
        job.getRun().configure(ChunkSource.of(createAccounts(10)), 5, false, null, false);
        job.getRun().position = 5;

        Assert.areEqual(null, job.nextPageOrNull(), 'No page should follow the final chunk.');
    }

    @IsTest
    private static void shouldHaltRunAfterFailedPageWhenConfigured() {
        MarkingChunkJob stopping = new MarkingChunkJob();
        stopping.getRun().configure(ChunkSource.of(createAccounts(10)), 5, true, null, false);

        Assert.isTrue(
            stopping.getRun().isHaltedBy(true),
            'A failed page must halt the run when stopRemainingChunksOnFailure is set.'
        );
        Assert.isFalse(
            stopping.getRun().isHaltedBy(false),
            'A page that succeeded must not halt the run.'
        );
    }

    @IsTest
    private static void shouldContinueRemainingChunksOnFailureByDefault() {
        MarkingChunkJob continuing = new MarkingChunkJob();
        continuing.getRun().configure(ChunkSource.of(createAccounts(10)), 5, false, null, false);

        Assert.isFalse(
            continuing.getRun().isHaltedBy(true),
            'A failed chunk must not halt the run by default.'
        );
        Assert.areNotEqual(
            null,
            continuing.nextPageOrNull(),
            'The run continues to the next page after a failed page.'
        );
    }

    @IsTest
    private static void shouldCarryFailedPageFlagToLaterPages() {
        MarkingChunkJob job = new MarkingChunkJob();
        job.getRun().configure(ChunkSource.of(createAccounts(6)), 2, false, null, false);
        job.hasFailed = true;

        ChunkJob nextPage = job.nextPageOrNull();

        Assert.isTrue(
            nextPage.getRun().hasFailedPage,
            'The run remembers a failed page so the run outcome stays FAILURE.'
        );
        Assert.isFalse(nextPage.hasFailed, 'The next page starts clean.');
    }

    @IsTest
    private static void shouldTreatEmptySourceAsNoOp() {
        Async.Result result = Async.chunk(
                new MarkingChunkJob(),
                ChunkSource.of(new List<Account>())
            )
            .enqueue();

        Assert.areEqual(null, result.salesforceJobId, 'An empty source should enqueue nothing.');
        Assert.isTrue(result.queueableChainState.jobs.isEmpty());
    }

    @IsTest
    private static void shouldStillRunChainedJobsWhenSourceIsEmpty() {
        Test.startTest();
        Async.queueable(new ProcessedCountMarkerJob('EMPTY_SOURCE'))
            .chunk(new MarkingChunkJob(), ChunkSource.of(new List<Account>()))
            .enqueue();
        Test.stopTest();

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Account WHERE Name = 'EMPTY_SOURCE'],
            'An empty chunk source must not swallow the jobs already chained.'
        );
    }

    @IsTest
    private static void shouldRejectInvalidChunkSize() {
        ChunkBuilder builder = Async.chunk(
            new MarkingChunkJob(),
            ChunkSource.of(createAccounts(1))
        );
        for (Integer invalid : new List<Integer>{ 0, -1, null }) {
            try {
                builder.chunkSize(invalid);
                Assert.fail('chunkSize ' + invalid + ' should be rejected.');
            } catch (Exception ex) {
                Assert.areEqual(ChunkBuilder.ERROR_MESSAGE_INVALID_CHUNK_SIZE, ex.getMessage());
            }
        }
    }

    @IsTest
    private static void shouldRejectChunkSizeAboveTheCursorFetchCap() {
        createAccounts(1);
        ChunkBuilder builder = Async.chunk(
            new MarkingChunkJob(),
            ChunkSource.query('SELECT Id FROM Account')
        );

        try {
            builder.chunkSize(2001);
            Assert.fail('A cursor source cannot page more than 2000 records at a time.');
        } catch (Exception ex) {
            Assert.areEqual(
                'chunkSize must be between 1 and 2000 for this source',
                ex.getMessage()
            );
        }
        Assert.areNotEqual(
            null,
            builder.chunkSize(2000),
            'A chunk size at the cursor fetch cap is allowed.'
        );
    }

    @IsTest
    private static void shouldNotCapChunkSizeForAnInMemorySource() {
        ChunkBuilder builder = Async.chunk(
            new MarkingChunkJob(),
            ChunkSource.of(createAccounts(1))
        );

        Assert.areEqual(
            null,
            ChunkSource.of(new List<Account>()).maxChunkSize(),
            'An in-memory source has no cursor fetch ceiling.'
        );
        Assert.areNotEqual(
            null,
            builder.chunkSize(5000),
            'An in-memory source is bounded by the job body, not by a page ceiling.'
        );
    }

    @IsTest
    private static void shouldExposeCursorFetchCapOnCursorSource() {
        createAccounts(1);

        Assert.areEqual(2000, ChunkSource.query('SELECT Id FROM Account').maxChunkSize());
    }

    @IsTest
    private static void shouldRejectNullJobAndSource() {
        try {
            Async.chunk(null, ChunkSource.of(createAccounts(1)));
            Assert.fail('A null job should be rejected.');
        } catch (Exception ex) {
            Assert.areEqual(ChunkBuilder.ERROR_MESSAGE_NULL_JOB, ex.getMessage());
        }
        try {
            Async.chunk(new MarkingChunkJob(), null);
            Assert.fail('A null source should be rejected.');
        } catch (Exception ex) {
            Assert.areEqual(ChunkBuilder.ERROR_MESSAGE_NULL_SOURCE, ex.getMessage());
        }
    }

    @IsTest
    private static void shouldRejectRetryAboveCapOnChunk() {
        ChunkBuilder builder = Async.chunk(
            new MarkingChunkJob(),
            ChunkSource.of(createAccounts(1))
        );
        try {
            builder.retry(QueueableManager.MAX_RETRY_CAP + 1);
            Assert.fail('Retry above the cap should be rejected.');
        } catch (Exception ex) {
            Assert.areEqual(
                QueueableManager.ERROR_MESSAGE_MAX_RETRIES_EXCEEDS_CAP,
                ex.getMessage()
            );
        }
    }

    @IsTest
    private static void shouldAccumulateJobStateAcrossChunks() {
        List<Account> accounts = createAccounts(6);

        Test.startTest();
        Async.chunk(new TotallingChunkJob(), ChunkSource.of(accounts)).chunkSize(2).enqueue();
        Test.stopTest();

        Set<String> runningTotals = new Set<String>();
        for (Account marker : [SELECT Site FROM Account WHERE Name = 'RUNNING_TOTAL']) {
            runningTotals.add(marker.Site);
        }
        Assert.areEqual(
            new Set<String>{ '2', '4', '6' },
            runningTotals,
            'A member mutated in work() keeps accumulating on every later page.'
        );
    }

    @IsTest
    private static void shouldPageRecordsFromAConsumerDefinedSource() {
        Test.startTest();
        Async.chunk(new CountingChunkJob(), new SyntheticChunkSource(2500))
            .chunkSize(1000)
            .enqueue();
        Test.stopTest();

        Set<String> runningTotals = new Set<String>();
        for (Account marker : [SELECT Site FROM Account WHERE Name = 'SYNTHETIC_TOTAL']) {
            runningTotals.add(marker.Site);
        }
        Assert.areEqual(
            new Set<String>{ '1000', '2000', '2500' },
            runningTotals,
            'A custom ChunkSource pages 2500 fabricated records without any DML behind it.'
        );
    }

    @IsTest
    private static void shouldInjectQueueableMockIntoAChunkPage() {
        List<Account> accounts = createAccounts(2);
        Id mockJobId = AsyncApexJob.SObjectType.getDescribe().getKeyPrefix() + '000000000001AAA';
        AsyncMock.whenQueueable('chunk-page')
            .thenReturn(new AsyncMock.MockQueueableContext().setJobId(mockJobId));

        Test.startTest();
        Async.chunk(new ContextReadingChunkJob(), ChunkSource.of(accounts))
            .chunkSize(2)
            .mockId('chunk-page')
            .enqueue();
        Test.stopTest();

        Assert.areEqual(
            String.valueOf(mockJobId),
            [SELECT Site FROM Account WHERE Name = 'MOCKED_CONTEXT' LIMIT 1].Site,
            'A chunk page reads the mocked QueueableContext like any other job.'
        );
    }

    @IsTest
    private static void shouldFailAJobFromAQueueableMock() {
        QueueableChain chain = new QueueableChain();
        chain.queueableJobSettingByJobName = resultsEnabledForAll();
        AsyncMock.whenQueueable('mocked-failure')
            .thenThrow(new CustomException(CUSTOM_ERROR_MESSAGE));

        Test.startTest();
        QueueableManager.get().setChain(chain);
        Async.queueable(new AccountCreatorJob('never runs'))
            .mockId('mocked-failure')
            .continueOnJobExecuteFail()
            .enqueue();
        Test.stopTest();

        AsyncResult__c result = [
            SELECT Status__c, ExceptionType__c, ExceptionMessage__c
            FROM AsyncResult__c
            LIMIT 1
        ];
        Assert.areEqual(
            QueueableManager.STATUS_FAILED,
            result.Status__c,
            'A mocked failure settles through the same path a real one does.'
        );
        Assert.areEqual(CUSTOM_ERROR_MESSAGE, result.ExceptionMessage__c);
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Account],
            'The job body never runs when its execution is mocked to throw.'
        );
    }

    @IsTest
    private static void shouldFailOnlyTheMockedChunkPage() {
        List<Account> accounts = createAccounts(6);
        AsyncMock.whenQueueable('recalc-run')
            .thenReturn(new AsyncMock.MockQueueableContext())
            .thenThrow(new CustomException(CUSTOM_ERROR_MESSAGE))
            .thenReturn(new AsyncMock.MockQueueableContext());

        Test.startTest();
        Async.chunk(new MarkingChunkJob(), ChunkSource.of(accounts))
            .chunkSize(2)
            .mockId('recalc-run')
            .enqueue();
        Test.stopTest();

        Assert.areEqual(
            4,
            [SELECT COUNT() FROM Account WHERE Site = :CHUNK_PROCESSED],
            'The mock queue picks which page fails; the rest of the run still processes.'
        );
    }

    @IsTest
    private static void shouldHaltRunFromAMockedPageFailure() {
        List<Account> accounts = createAccounts(6);
        AsyncMock.whenQueueable('recalc-run')
            .thenReturn(new AsyncMock.MockQueueableContext())
            .thenThrow(new CustomException(CUSTOM_ERROR_MESSAGE));

        Test.startTest();
        Async.chunk(new MarkingChunkJob(), ChunkSource.of(accounts))
            .chunkSize(2)
            .mockId('recalc-run')
            .stopRemainingChunksOnFailure()
            .enqueue();
        Test.stopTest();

        Assert.areEqual(
            2,
            [SELECT COUNT() FROM Account WHERE Site = :CHUNK_PROCESSED],
            'A mocked page failure halts the run like a real one.'
        );
    }

    @IsTest
    private static void shouldMockFinalizerOutcomeForAChunkPage() {
        List<Account> accounts = createAccounts(2);
        AsyncMock.whenFinalizer('chunk-error-handler').thenThrow(new DmlException('Page blew up'));

        Test.startTest();
        Async.chunk(new FinalizerAttachingChunkJob('chunk-error-handler'), ChunkSource.of(accounts))
            .chunkSize(2)
            .enqueue();
        Test.stopTest();

        Assert.areEqual(
            'Page blew up',
            [SELECT Description FROM Account WHERE Name = 'Error Log' LIMIT 1].Description,
            'A page finalizer can be told its page failed without the page actually failing.'
        );
    }

    @IsTest
    private static void shouldFailAndRetryAPageWhenTheSourceThrows() {
        QueueableChain chain = new QueueableChain();
        chain.queueableJobSettingByJobName = resultsEnabledForAll();

        Test.startTest();
        QueueableManager.get().setChain(chain);
        Async.chunk(new MarkingChunkJob(), new ExplodingChunkSource())
            .chunkSize(2)
            .retry(1)
            .enqueue();
        Test.stopTest();

        AsyncResult__c result = [
            SELECT Status__c, ExceptionMessage__c, RetryAttempts__c
            FROM AsyncResult__c
            LIMIT 1
        ];
        Assert.areEqual(
            QueueableManager.STATUS_FAILED,
            result.Status__c,
            'A source that throws fails the page instead of silently ending the run.'
        );
        Assert.areEqual(CUSTOM_ERROR_MESSAGE, result.ExceptionMessage__c);
        Assert.areEqual(1, result.RetryAttempts__c, 'The page retried before it settled.');
    }

    @IsTest
    private static void shouldChainRunWithoutEnqueueingIt() {
        List<Account> accounts = createAccounts(2);

        Async.Result result = Async.chunk(new MarkingChunkJob(), ChunkSource.of(accounts))
            .chunkSize(2)
            .chain();

        Assert.areNotEqual(
            null,
            result.customJobId,
            'chain() returns the run handle so later jobs can depend on it.'
        );
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Account WHERE Site = :CHUNK_PROCESSED],
            'chain() adds the run to the chain without enqueuing anything.'
        );
    }

    @IsTest
    private static void shouldRunASecondChunkRunAfterTheFirstOneFinishes() {
        List<Account> accounts = createAccounts(4);

        Test.startTest();
        Async.chunk(new LabelingChunkJob('FIRST'), ChunkSource.of(accounts))
            .chunkSize(2)
            .chunk(new LabelingChunkJob('SECOND'), ChunkSource.of(accounts))
            .chunkSize(2)
            .enqueue();
        Test.stopTest();

        Assert.areEqual(
            4,
            [SELECT COUNT() FROM Account WHERE Site = 'SECOND'],
            'The second run overwrites the first, so it ran after every page of run one.'
        );
    }

    @IsTest
    private static void shouldGateASecondChunkRunOnTheFirstRunOutcome() {
        List<Account> accounts = accountsWithOneFailingRecord();

        Test.startTest();
        Async.chunk(new FailMarkedChunkJob(), ChunkSource.of(accounts))
            .chunkSize(2)
            .chunk(new LabelingChunkJob('SECOND'), ChunkSource.of(accounts))
            .chunkSize(2)
            .dependsOn(Async.afterPrevious().succeeded())
            .enqueue();
        Test.stopTest();

        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Account WHERE Site = 'SECOND'],
            'dependsOn(previous) resolves against the first run outcome, which failed.'
        );
    }

    @IsTest
    private static void shouldOpenACursorInTheRequestedAccessLevel() {
        createAccounts(2);

        ChunkSource userMode = ChunkSource.query('SELECT Id FROM Account', AccessLevel.USER_MODE);
        ChunkSource systemMode = ChunkSource.query(
            'SELECT Id FROM Account WHERE Name LIKE :prefix',
            new Map<String, Object>{ 'prefix' => 'Chunk%' },
            AccessLevel.SYSTEM_MODE
        );

        Assert.areEqual(2, userMode.getNumRecords(), 'The admin running the test sees both.');
        Assert.areEqual(2, systemMode.getNumRecords(), 'Binds and access level combine.');
    }

    @IsTest
    private static void shouldChainNothingWhenSourceIsEmpty() {
        Async.Result result = Async.chunk(
                new MarkingChunkJob(),
                ChunkSource.of(new List<Account>())
            )
            .chain();

        Assert.areEqual(null, result.customJobId, 'An empty source chains no run.');
        Assert.isTrue(result.queueableChainState.jobs.isEmpty());
    }

    @IsTest
    private static void shouldRunChunkRunWhenItsDependencySucceeded() {
        List<Account> accounts = createAccounts(4);

        Test.startTest();
        Async.queueable(new ProcessedCountMarkerJob('GATE'))
            .chunk(new MarkingChunkJob(), ChunkSource.of(accounts))
            .chunkSize(2)
            .dependsOn(Async.afterPrevious().succeeded())
            .enqueue();
        Test.stopTest();

        Assert.areEqual(
            4,
            [SELECT COUNT() FROM Account WHERE Site = :CHUNK_PROCESSED],
            'The run starts once the job it depends on succeeded.'
        );
    }

    @IsTest
    private static void shouldSkipChunkRunWhenItsDependencyFailed() {
        List<Account> accounts = createAccounts(4);

        Test.startTest();
        Async.queueable(new FailureQueueableTest())
            .continueOnJobExecuteFail()
            .chunk(new MarkingChunkJob(), ChunkSource.of(accounts))
            .chunkSize(2)
            .dependsOn(Async.afterPrevious().succeeded())
            .enqueue();
        Test.stopTest();

        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Account WHERE Site = :CHUNK_PROCESSED],
            'The whole run is skipped when the job it depends on failed.'
        );
    }

    @IsTest
    private static void shouldRejectInvalidDependencyOnChunk() {
        ChunkBuilder builder = Async.chunk(
            new MarkingChunkJob(),
            ChunkSource.of(createAccounts(1))
        );
        try {
            builder.dependsOn(null);
            Assert.fail('A dependency without an outcome should be rejected.');
        } catch (Exception ex) {
            Assert.areEqual(QueueableManager.ERROR_MESSAGE_INVALID_DEPENDENCY, ex.getMessage());
        }
        try {
            builder.dependsOn(Async.afterPrevious().succeeded());
            Assert.fail('afterPrevious() without a previously chained job should be rejected.');
        } catch (Exception ex) {
            Assert.areEqual(
                QueueableManager.ERROR_MESSAGE_DEPENDS_ON_PREVIOUS_WITHOUT_JOB,
                ex.getMessage()
            );
        }
    }

    @IsTest
    private static void shouldYieldIdOnlyShellsWhenSourceIsBuiltFromIds() {
        List<Account> accounts = createAccounts(5);
        ChunkSource source = ChunkSource.ofIds(new Map<Id, Account>(accounts).keySet());

        List<SObject> page = source.fetch(0, 5);

        Assert.areEqual(5, page.size());
        Assert.areEqual(
            new Map<Id, Account>(accounts).keySet(),
            new Map<Id, SObject>(page).keySet(),
            'A job reads ids straight off the page with new Map<Id, SObject>(chunk).keySet().'
        );
    }

    @IsTest
    private static void shouldExposeInMemorySourceRecordsAndSize() {
        List<Account> accounts = createAccounts(5);
        ChunkSource source = ChunkSource.of(accounts);

        Assert.areEqual(5, source.getNumRecords());
        Assert.areEqual(2, source.fetch(0, 2).size());
        Assert.areEqual(
            1,
            source.fetch(4, 5).size(),
            'A short final page must clamp to the remainder.'
        );
    }

    @IsTest
    private static void shouldBuildIdSourceRecordsWithIds() {
        List<Account> accounts = createAccounts(3);
        Set<Id> ids = new Map<Id, Account>(accounts).keySet();
        ChunkSource source = ChunkSource.ofIds(ids);

        Assert.areEqual(3, source.getNumRecords());
        Set<Id> fetched = new Set<Id>();
        for (SObject record : source.fetch(0, 3)) {
            fetched.add(record.Id);
        }
        Assert.areEqual(ids, fetched);
    }

    @IsTest
    private static void shouldTreatNullRecordsAsEmptySource() {
        Assert.areEqual(0, ChunkSource.ofIds(null).getNumRecords());
        Assert.areEqual(0, ChunkSource.of(null).getNumRecords());
    }

    @IsTest
    private static void shouldDelegateToCursorSource() {
        createAccounts(5);
        ChunkSource source = ChunkSource.cursor(Database.getCursor('SELECT Id FROM Account'));

        Assert.areEqual(5, source.getNumRecords());
        Assert.areEqual(2, source.fetch(0, 2).size());
    }

    @IsTest
    private static void shouldOpenCursorFromQuery() {
        createAccounts(4);
        ChunkSource source = ChunkSource.query('SELECT Id FROM Account');

        Assert.areEqual(4, source.getNumRecords());
    }

    @IsTest
    private static void shouldOpenCursorFromQueryWithBinds() {
        createAccounts(4);
        ChunkSource source = ChunkSource.query(
            'SELECT Id FROM Account WHERE Name = :accountName',
            new Map<String, Object>{ 'accountName' => 'Chunk 1' }
        );

        Assert.areEqual(1, source.getNumRecords(), 'Bind variables must reach the cursor.');
    }

    @IsTest
    private static void shouldRejectNullCursorAndBlankQuery() {
        try {
            ChunkSource.cursor(null);
            Assert.fail('A null cursor should be rejected.');
        } catch (Exception ex) {
            Assert.areEqual(ChunkSource.ERROR_MESSAGE_NULL_CURSOR, ex.getMessage());
        }
        try {
            ChunkSource.query('   ');
            Assert.fail('A blank query should be rejected.');
        } catch (Exception ex) {
            Assert.areEqual(ChunkSource.ERROR_MESSAGE_BLANK_QUERY, ex.getMessage());
        }
        try {
            ChunkSource.query('   ', new Map<String, Object>());
            Assert.fail('A blank query with binds should be rejected.');
        } catch (Exception ex) {
            Assert.areEqual(ChunkSource.ERROR_MESSAGE_BLANK_QUERY, ex.getMessage());
        }
    }

    @IsTest
    private static void shouldOrderJobsOfEqualPriorityByChainSequence() {
        QueueableJobTest1 first = new QueueableJobTest1();
        first.uniqueName = 'first';
        first.chainSequence = 1;
        QueueableJobTest2 second = new QueueableJobTest2();
        second.uniqueName = 'second';
        second.chainSequence = 2;

        List<QueueableJob> jobs = new List<QueueableJob>{ second, first };
        jobs.sort();

        Assert.areEqual('first', jobs[0].uniqueName, 'Equal priority keeps the chained order.');
        Assert.areEqual('second', jobs[1].uniqueName);
    }

    @IsTest
    private static void shouldRunEveryChunkBeforeTheNextChainedJob() {
        List<Account> accounts = createAccounts(6);

        Test.startTest();
        Async.chunk(new MarkingChunkJob(), ChunkSource.of(accounts))
            .chunkSize(2)
            .chain(new ProcessedCountMarkerJob('AFTER_RUN'))
            .enqueue();
        Test.stopTest();

        Assert.areEqual(
            '6',
            processedCountSeenBy('AFTER_RUN'),
            'A job chained after the run must wait for every page.'
        );
    }

    @IsTest
    private static void shouldRunChunkRunAfterAnEarlierChainedJob() {
        List<Account> accounts = createAccounts(4);

        Test.startTest();
        Async.queueable(new ProcessedCountMarkerJob('BEFORE_RUN'))
            .chunk(new MarkingChunkJob(), ChunkSource.of(accounts))
            .chunkSize(2)
            .enqueue();
        Test.stopTest();

        Assert.areEqual(
            '0',
            processedCountSeenBy('BEFORE_RUN'),
            'A job chained before the run must run first.'
        );
        Assert.areEqual(4, [SELECT COUNT() FROM Account WHERE Site = :CHUNK_PROCESSED]);
    }

    @IsTest
    private static void shouldLetHigherPriorityJobPreemptTheNextChunk() {
        List<Account> accounts = createAccounts(6);
        PreemptingChunkJob job = new PreemptingChunkJob();
        job.preemptPriority = 1;

        Test.startTest();
        Async.chunk(job, ChunkSource.of(accounts)).chunkSize(2).priority(5).enqueue();
        Test.stopTest();

        Assert.areEqual(
            '2',
            processedCountSeenBy('PREEMPT'),
            'A higher priority job added mid-run runs before the next page.'
        );
        Assert.areEqual(
            6,
            [SELECT COUNT() FROM Account WHERE Site = :CHUNK_PROCESSED],
            'The run resumes after the preempting job.'
        );
    }

    @IsTest
    private static void shouldRunLowerPriorityJobAfterTheWholeRun() {
        List<Account> accounts = createAccounts(6);
        PreemptingChunkJob job = new PreemptingChunkJob();
        job.preemptPriority = 9;

        Test.startTest();
        Async.chunk(job, ChunkSource.of(accounts)).chunkSize(2).priority(5).enqueue();
        Test.stopTest();

        Assert.areEqual(
            '6',
            processedCountSeenBy('PREEMPT'),
            'A lower priority job added mid-run waits for the whole run.'
        );
    }

    @IsTest
    private static void shouldRunDependentJobWhenEveryChunkSucceeded() {
        List<Account> accounts = createAccounts(6);

        Test.startTest();
        Async.chunk(new MarkingChunkJob(), ChunkSource.of(accounts))
            .chunkSize(2)
            .chain(new ProcessedCountMarkerJob('DEPENDENT'))
            .dependsOn(Async.afterPrevious().succeeded())
            .enqueue();
        Test.stopTest();

        Assert.areEqual(
            '6',
            processedCountSeenBy('DEPENDENT'),
            'The run outcome is SUCCESS when every page passed.'
        );
    }

    @IsTest
    private static void shouldSkipDependentJobWhenAnyChunkFailed() {
        List<Account> accounts = accountsWithOneFailingRecord();

        Test.startTest();
        Async.chunk(new FailMarkedChunkJob(), ChunkSource.of(accounts))
            .chunkSize(2)
            .chain(new ProcessedCountMarkerJob('DEPENDENT'))
            .dependsOn(Async.afterPrevious().succeeded())
            .enqueue();
        Test.stopTest();

        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Account WHERE Name = 'DEPENDENT'],
            'One failed page makes the whole run outcome FAILURE.'
        );
    }

    @IsTest
    private static void shouldRunDependentJobOnFinishedRunEvenAfterAFailedChunk() {
        List<Account> accounts = accountsWithOneFailingRecord();

        Test.startTest();
        Async.chunk(new FailMarkedChunkJob(), ChunkSource.of(accounts))
            .chunkSize(2)
            .chain(new ProcessedCountMarkerJob('DEPENDENT'))
            .dependsOn(Async.afterPrevious().finished())
            .enqueue();
        Test.stopTest();

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Account WHERE Name = 'DEPENDENT'],
            'finished() runs the dependent job whatever the run outcome was.'
        );
    }

    @IsTest
    private static void shouldRecordSummaryResultWhenRunHaltsOnFailure() {
        List<Account> accounts = accountsWithOneFailingRecord();
        QueueableChain chain = new QueueableChain();
        chain.queueableJobSettingByJobName = resultsEnabledForAll();

        Test.startTest();
        QueueableManager.get().setChain(chain);
        Async.chunk(new FailMarkedChunkJob(), ChunkSource.of(accounts))
            .chunkSize(2)
            .stopRemainingChunksOnFailure()
            .enqueue();
        Test.stopTest();

        List<AsyncResult__c> stopped = [
            SELECT SkipReason__c
            FROM AsyncResult__c
            WHERE Status__c = :QueueableManager.STATUS_SKIPPED_CHUNK_STOPPED
        ];
        Assert.areEqual(1, stopped.size(), 'A halted run records one summary result.');
        Assert.isTrue(
            stopped[0].SkipReason__c.contains('page 3 of 3'),
            'The summary states where the run stopped: ' + stopped[0].SkipReason__c
        );
        Assert.isTrue(
            stopped[0].SkipReason__c.contains('2 record(s) were not processed'),
            'The summary states how much work was left: ' + stopped[0].SkipReason__c
        );
    }

    @IsTest
    private static void shouldRecordSummaryResultWhenChainStopsDuringRun() {
        List<Account> accounts = createAccounts(6);
        QueueableChain chain = new QueueableChain();
        chain.queueableJobSettingByJobName = resultsEnabledForAll();

        Test.startTest();
        QueueableManager.get().setChain(chain);
        Async.chunk(new ChainStoppingChunkJob(), ChunkSource.of(accounts)).chunkSize(2).enqueue();
        Test.stopTest();

        Assert.areEqual(
            2,
            [SELECT COUNT() FROM Account WHERE Site = :CHUNK_PROCESSED],
            'Async.stopChain() ends the run wherever it is.'
        );
        List<AsyncResult__c> stopped = [
            SELECT SkipReason__c
            FROM AsyncResult__c
            WHERE
                Status__c = :QueueableManager.STATUS_SKIPPED_CHAIN_STOPPED
                AND SkipReason__c LIKE '%not processed%'
        ];
        Assert.areEqual(1, stopped.size(), 'A stopped chain records what the run left behind.');
        Assert.isTrue(
            stopped[0].SkipReason__c.contains('page 2 of 3'),
            'The summary points at the first page that never ran: ' + stopped[0].SkipReason__c
        );
    }

    private static String processedCountSeenBy(String tag) {
        return [SELECT Site FROM Account WHERE Name = :tag LIMIT 1].Site;
    }

    private static List<Account> createAccounts(Integer count) {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < count; i++) {
            accounts.add(new Account(Name = 'Chunk ' + i));
        }
        insert accounts;
        return accounts;
    }

    private static List<Account> accountsWithOneFailingRecord() {
        List<Account> accounts = new List<Account>{
            new Account(Name = 'ok first'),
            new Account(Name = 'ok second'),
            new Account(Name = 'FAIL third'),
            new Account(Name = 'ok fourth'),
            new Account(Name = 'ok fifth'),
            new Account(Name = 'ok sixth')
        };
        insert accounts;
        return accounts;
    }

    private static void markProcessed(List<SObject> chunk, String marker) {
        List<Account> toUpdate = new List<Account>();
        for (SObject record : chunk) {
            toUpdate.add(new Account(Id = record.Id, Site = marker));
        }
        update toUpdate;
    }

    private class MarkingChunkJob extends ChunkJob {
        public override void work(List<SObject> chunk) {
            markProcessed(chunk, CHUNK_PROCESSED);
        }
    }

    private class LabelingChunkJob extends ChunkJob {
        private String label;

        public LabelingChunkJob(String label) {
            this.label = label;
        }

        public override void work(List<SObject> chunk) {
            markProcessed(chunk, label);
        }
    }

    private class FailMarkedChunkJob extends ChunkJob {
        public override void work(List<SObject> chunk) {
            for (SObject record : chunk) {
                Account account = (Account) record;
                if (account.Name != null && account.Name.contains('FAIL')) {
                    throw new CustomException(AsyncTest.CUSTOM_ERROR_MESSAGE);
                }
            }
            markProcessed(chunk, CHUNK_PROCESSED);
        }
    }

    private class TotallingChunkJob extends ChunkJob {
        public Integer processedSoFar = 0;

        public override void work(List<SObject> chunk) {
            processedSoFar += chunk.size();
            markProcessed(chunk, CHUNK_PROCESSED);
            insert new Account(Name = 'RUNNING_TOTAL', Site = String.valueOf(processedSoFar));
        }
    }

    private class CountingChunkJob extends ChunkJob {
        public Integer seenSoFar = 0;

        public override void work(List<SObject> chunk) {
            seenSoFar += chunk.size();
            insert new Account(Name = 'SYNTHETIC_TOTAL', Site = String.valueOf(seenSoFar));
        }
    }

    private class FinalizerAttachingChunkJob extends ChunkJob {
        private String finalizerMockId;

        public FinalizerAttachingChunkJob(String finalizerMockId) {
            this.finalizerMockId = finalizerMockId;
        }

        public override void work(List<SObject> chunk) {
            Async.queueable(new ErrorHandlerFinalizer()).mockId(finalizerMockId).attachFinalizer();
        }
    }

    private class ContextReadingChunkJob extends ChunkJob {
        public override void work(List<SObject> chunk) {
            insert new Account(
                Name = 'MOCKED_CONTEXT',
                Site = String.valueOf(this.queueableCtx?.getJobId())
            );
        }
    }

    private class ExplodingChunkSource extends ChunkSource {
        public override Integer getNumRecords() {
            return 4;
        }

        public override List<SObject> fetch(Integer position, Integer count) {
            throw new CustomException(AsyncTest.CUSTOM_ERROR_MESSAGE);
        }
    }

    private class SyntheticChunkSource extends ChunkSource {
        private Integer total;

        public SyntheticChunkSource(Integer total) {
            this.total = total;
        }

        public override Integer getNumRecords() {
            return total;
        }

        public override List<SObject> fetch(Integer position, Integer count) {
            List<Account> page = new List<Account>();
            for (Integer i = position; i < Math.min(position + count, total); i++) {
                page.add(new Account(Name = 'Synthetic ' + i));
            }
            return page;
        }
    }

    private class ChainStoppingChunkJob extends ChunkJob {
        public override void work(List<SObject> chunk) {
            markProcessed(chunk, CHUNK_PROCESSED);
            Async.stopChain();
        }
    }

    private class PreemptingChunkJob extends ChunkJob {
        public Integer preemptPriority;

        public override void work(List<SObject> chunk) {
            markProcessed(chunk, CHUNK_PROCESSED);
            if (getRun().position == 0) {
                Async.queueable(new ProcessedCountMarkerJob('PREEMPT'))
                    .priority(preemptPriority)
                    .chain();
            }
        }
    }

    private class ProcessedCountMarkerJob extends QueueableJob {
        private String tag;

        public ProcessedCountMarkerJob(String tag) {
            this.tag = tag;
        }

        public override void work() {
            insert new Account(
                Name = tag,
                Site = String.valueOf([SELECT COUNT() FROM Account WHERE Site = :CHUNK_PROCESSED])
            );
        }
    }
}
