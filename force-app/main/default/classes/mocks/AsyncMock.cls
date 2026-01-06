@IsTest
public class AsyncMock {

    private static Map<String, FinalizerMockSetup> finalizerSetups = new Map<String, FinalizerMockSetup>();
    private static Map<String, QueueableMockSetup> queueableSetups = new Map<String, QueueableMockSetup>();
    private static FinalizerMockSetup defaultFinalizerSetup;
    private static QueueableMockSetup defaultQueueableSetup;

    public static FinalizerMockSetup whenFinalizer(String mockId) {
        FinalizerMockSetup setup = new FinalizerMockSetup();
        finalizerSetups.put(mockId, setup);
        return setup;
    }

    public static FinalizerMockSetup whenFinalizerDefault() {
        defaultFinalizerSetup = new FinalizerMockSetup();
        return defaultFinalizerSetup;
    }

    public static QueueableMockSetup whenQueueable(String mockId) {
        QueueableMockSetup setup = new QueueableMockSetup();
        queueableSetups.put(mockId, setup);
        return setup;
    }

    public static QueueableMockSetup whenQueueableDefault() {
        defaultQueueableSetup = new QueueableMockSetup();
        return defaultQueueableSetup;
    }

    public static FinalizerContext getFinalizerContext(String mockId) {
        FinalizerMockSetup setup = finalizerSetups.get(mockId);
        if (setup == null) {
            setup = defaultFinalizerSetup;
        }
        return setup?.getNext();
    }

    public static QueueableContext getQueueableContext(String mockId) {
        QueueableMockSetup setup = queueableSetups.get(mockId);
        if (setup == null) {
            setup = defaultQueueableSetup;
        }
        return setup?.getNext();
    }

    public static void reset() {
        finalizerSetups.clear();
        queueableSetups.clear();
        defaultFinalizerSetup = null;
        defaultQueueableSetup = null;
    }

    public class FinalizerMockSetup {
        private List<FinalizerContext> contexts = new List<FinalizerContext>();

        public FinalizerMockSetup thenReturn(FinalizerContext ctx) {
            contexts.add(ctx);
            return this;
        }

        public FinalizerMockSetup thenReturn(ParentJobResult result) {
            return thenReturn(new MockFinalizerContext().setResult(result));
        }

        public FinalizerMockSetup thenThrow(Exception ex) {
            return thenReturn(new MockFinalizerContext().setException(ex));
        }

        public FinalizerContext getNext() {
            if (contexts.isEmpty()) {
                return null;
            }
            if (contexts.size() == 1) {
                return contexts.get(0);
            }
            return contexts.remove(0);
        }
    }

    public class QueueableMockSetup {
        private List<QueueableContext> contexts = new List<QueueableContext>();

        public QueueableMockSetup thenReturn(QueueableContext ctx) {
            contexts.add(ctx);
            return this;
        }

        public QueueableMockSetup thenReturn(Id jobId) {
            return thenReturn(new MockQueueableContext().setJobId(jobId));
        }

        public QueueableContext getNext() {
            if (contexts.isEmpty()) {
                return null;
            }
            if (contexts.size() == 1) {
                return contexts.get(0);
            }
            return contexts.remove(0);
        }
    }

    public class MockFinalizerContext implements System.FinalizerContext {
        private ParentJobResult result = ParentJobResult.SUCCESS;
        private Exception ex;
        private Id jobId;

        public MockFinalizerContext setResult(ParentJobResult result) {
            this.result = result;
            return this;
        }

        public MockFinalizerContext setException(Exception ex) {
            this.ex = ex;
            this.result = ParentJobResult.UNHANDLED_EXCEPTION;
            return this;
        }

        public MockFinalizerContext setJobId(Id jobId) {
            this.jobId = jobId;
            return this;
        }

        public ParentJobResult getResult() {
            return result;
        }

        public Exception getException() {
            return ex;
        }

        public Id getAsyncApexJobId() {
            return jobId;
        }

        public String getRequestId() {
            return 'mock-request-id';
        }
    }

    public class MockQueueableContext implements System.QueueableContext {
        private Id jobId;

        public MockQueueableContext setJobId(Id jobId) {
            this.jobId = jobId;
            return this;
        }

        public Id getJobId() {
            return jobId;
        }
    }

    public class MockSchedulableContext implements System.SchedulableContext {
        private Id triggerId;

        public MockSchedulableContext setTriggerId(Id triggerId) {
            this.triggerId = triggerId;
            return this;
        }

        public Id getTriggerId() {
            return triggerId;
        }
    }

    public class MockBatchableContext implements Database.BatchableContext {
        private Id jobId;
        private Id childJobId;

        public MockBatchableContext setJobId(Id jobId) {
            this.jobId = jobId;
            return this;
        }

        public MockBatchableContext setChildJobId(Id childJobId) {
            this.childJobId = childJobId;
            return this;
        }

        public Id getJobId() {
            return jobId;
        }

        public Id getChildJobId() {
            return childJobId;
        }
    }
}
