@IsTest
public class NsTestLogging {
    public class NsLoggingException extends Exception {
    }

    public class LoggedJob extends btcdev.QueueableJob {
        public override void work() {
            insert new Account(Name = 'NS-LOGGED-WORK');
        }
    }

    public class LoggedFailingJob extends btcdev.QueueableJob implements btcdev.Async.Retryable {
        public override void work() {
            throw new NsLoggingException('ns logging failure');
        }

        public void resetBeforeRetry(Integer attempt) {
        }
    }

    public class SelfListeningJob extends btcdev.QueueableJob implements btcdev.Async.OnJobSucceeded {
        public override void work() {
        }

        public void onJobSucceeded(btcdev.Async.JobContext ctx) {
            insert new Account(Name = 'NS-SELF-LISTENER', Description = ctx.info.get('team'));
        }
    }

    private static Integer countOf(String name) {
        return [SELECT COUNT() FROM Account WHERE Name = :name];
    }

    private static void registerLogger() {
        btcdev.QueueableChain chain = btcdev.QueueableManager.get().getChain();
        chain.queueableJobSettingByJobName = new Map<String, QueueableJobSetting__mdt>{
            'All' => new QueueableJobSetting__mdt(
                QueueableJobName__c = 'All',
                LoggerClass__c = 'NsAsyncLogger'
            )
        };
    }

    @IsTest
    static void shouldReachAGlobalSubscriberLoggerFromInsideThePackage() {
        registerLogger();

        Test.startTest();
        btcdev.Async.queueable(new LoggedJob()).info('team', 'platform').enqueue();
        Test.stopTest();

        System.assertEquals(
            1,
            countOf('NS-LOG-ENQUEUED'),
            'Type.forName must reach a global subscriber class from package code'
        );
        System.assertEquals(1, countOf('NS-LOG-SUCCEEDED'), 'Success must reach the logger');

        String detail = [SELECT Description FROM Account WHERE Name = 'NS-LOG-ENQUEUED' LIMIT 1]
        .Description;
        System.assert(
            detail.endsWith('|platform'),
            'info() must survive into the context across the namespace, but was: ' + detail
        );
    }

    @IsTest
    static void shouldReportFailureAndRetryEventsToTheSubscriberLogger() {
        registerLogger();

        Test.startTest();
        btcdev.Async.queueable(new LoggedFailingJob())
            .continueOnJobExecuteFail()
            .retry(1)
            .enqueue();
        Test.stopTest();

        System.assertEquals(1, countOf('NS-LOG-RETRY'), 'The queued retry must reach the logger');
        System.assertEquals(
            1,
            countOf('NS-LOG-FAILED'),
            'The terminal failure must reach the logger exactly once'
        );
    }

    @IsTest
    static void shouldFireAJobsOwnListenerWithoutAnyRegistration() {
        Test.startTest();
        btcdev.Async.queueable(new SelfListeningJob()).info('team', 'billing').enqueue();
        Test.stopTest();

        System.assertEquals(
            1,
            countOf('NS-SELF-LISTENER'),
            'A job implementing the interface needs no Custom Metadata at all'
        );
    }
}
