@IsTest
private class AsyncTest {
    private static final String ACCOUNT_NAME = 'Test Account';
    private static final String CUSTOM_ERROR_MESSAGE = 'Something goes wrong.';
    private static final String DUPLICATE_SIGNATURE_ERROR_MESSAGE = 'Attempt to enqueue job with duplicate queueable signature';
    private static final String TEST_SIGNATURE_NAME = 'SignatureName';

    @IsTest
    private static void shouldSchedule60QueueablesSuccessfully() {
        SuccessfulQueueableTest q = new SuccessfulQueueableTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Account]);
        Id initialQueuableChainBatchJobId;

        Test.startTest();
        for (Integer idx = 0; idx < 60; idx++) {
            Async.AsyncResult ar = Async.of(q).enqueue();
            if (Limits.getQueueableJobs() <= Limits.getLimitQueueableJobs()) {
                Assert.isFalse(ar.isChained, 'Should not be enqueued via batch.');
            } else {
                Assert.isTrue(ar.isChained, 'Should be enqueued via batch.');
            }
        }
        initialQueuableChainBatchJobId = Async.getQueueableChainBatchId();
        Test.stopTest();

        Assert.areEqual(51, [SELECT COUNT() FROM Account], 'Should have 51 job runs (50 queueable and 1 batch).');
        Assert.areEqual(
            1,
            [SELECT Id FROM AsyncApexJob WHERE ApexClass.Name = 'QueueableChainBatch' AND Status = 'Completed' AND Id = :initialQueuableChainBatchJobId].size(),
            'Should run only one batchable job with the rest, that should be successfully completed and with Id provided from framework.'
        );
    }

    @IsTest
    private static void shouldSchedule60QueueablesWitDelaySuccessfully() {
        SuccessfulQueueableTest q = new SuccessfulQueueableTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Account]);

        Test.startTest();
        for (Integer idx = 0; idx < 60; idx++) {
            Async.of(q)
                .delay(1)
                .enqueue();
        }
        Test.stopTest();

        Assert.areEqual(51, [SELECT COUNT() FROM Account], 'Should have 51 job runs (50 queueable and 1 batch).');
        Assert.areEqual(
            1,
            [SELECT Id FROM AsyncApexJob WHERE ApexClass.Name = 'QueueableChainBatch' AND Status = 'Completed'].size(),
            'Should run only one batchable job with the rest.'
        );
    }

    @IsTest
    private static void shouldSchedule60QueueablesSuccessfullyWithAllItemsFailedWithRollback() {
        FailureQueueableTest q = new FailureQueueableTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Account]);

        Test.startTest();
        for (Integer idx = 0; idx < 60; idx++) {
            Async.of(q)
                .continueOnJobExecuteFail()
                .rollbackOnJobExecuteFail()
                .enqueue();
        }
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Account], 'Should have no Accounts created.');
        Assert.areEqual(
            1,
            [SELECT Id FROM AsyncApexJob WHERE ApexClass.Name = 'QueueableChainBatch' AND Status = 'Completed'].size(),
            'Should run only one batchable job with the rest.'
        );
    }

    @IsTest
    private static void shouldSchedule60QueueablesSuccessfullyWithAllItemsFailedWithoutRollback() {
        FailureQueueableTest q = new FailureQueueableTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Account]);

        Test.startTest();
        for (Integer idx = 0; idx < 60; idx++) {
            Async.of(q)
                .continueOnJobExecuteFail()
                .enqueue();
        }
        Test.stopTest();

        Assert.areEqual(51, [SELECT COUNT() FROM Account], 'Inserted Accounts are not rollbacked.');
        Assert.areEqual(
            1,
            [SELECT Id FROM AsyncApexJob WHERE ApexClass.Name = 'QueueableChainBatch' AND Status = 'Completed'].size(),
            'Should run only one batchable job with the rest.'
        );
    }

    @IsTest
    private static void shouldOnlyScheduleOneJobDueToAsyncOptions() {
        SuccessfulQueueableTest q = new SuccessfulQueueableTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Account]);
        AsyncOptions options = new AsyncOptions();
        options.DuplicateSignature = QueueableDuplicateSignature.Builder().addString(TEST_SIGNATURE_NAME).build();

        Test.startTest();
        for (Integer idx = 0; idx < 50; idx++) {
            Async.of(q)
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
            Async.of(q)
                .asyncOptions(options)
                .enqueue();
            Async.of(q)
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
            Async.of(failureJob)
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
            Async.of(finalizer)
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
            Async.of(finalizer)
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
            Async.of(q)
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
        chain.disabledQueueableJobSettingByJobName = new Map<String, QueueableJobSetting__mdt>{
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
        chain.disabledQueueableJobSettingByJobName = new Map<String, QueueableJobSetting__mdt>{
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

    private class SuccessfulQueueableTest extends QueueableJob {
        public override void work() {
            insert new Account(Name = Async.getQueueableJobContext()?.currentJob?.uniqueName);
        }
    }

    private class FailureQueueableTest extends QueueableJob.WithCallouts {
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
            Async.of(new SuccessfulQueueableTest())
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

    private class CustomException extends Exception {
    }
}
