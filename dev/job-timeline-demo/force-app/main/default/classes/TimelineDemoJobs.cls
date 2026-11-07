/**
 * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
 *
 * v3.2.0
 **/
public class TimelineDemoJobs {
    public class DemoException extends Exception {
    }

    public class StepJob extends QueueableJob {
        public Integer index;
        public Integer spinMs = 300;
        public StepJob(Integer index) {
            this.index = index;
        }
        public override void work() {
            Long until = System.currentTimeMillis() + spinMs;
            while (System.currentTimeMillis() < until) {
            }
        }
    }

    public class FailingJob extends QueueableJob implements Async.Retryable {
        public String message;
        public FailingJob(String message) {
            this.message = message;
        }
        public void resetBeforeRetry(Integer attempt) {
        }
        public override void work() {
            throw new DemoException(message);
        }
    }

    public class FlakyJob extends QueueableJob implements Async.Retryable {
        public Integer succeedsOnAttempt;
        public FlakyJob(Integer succeedsOnAttempt) {
            this.succeedsOnAttempt = succeedsOnAttempt;
        }
        public void resetBeforeRetry(Integer attempt) {
        }
        public override void work() {
            if (retryAttempt < succeedsOnAttempt) {
                throw new DemoException('Timed out waiting for the pricing service (attempt ' + (retryAttempt + 1) + ')');
            }
        }
    }

    public class LinkingJob extends QueueableJob {
        public Id accountId;
        public LinkingJob(Id accountId) {
            this.accountId = accountId;
        }
        public override void work() {
            Async.linkRecord(accountId);
            Async.queueable(new StepJob(99)).name('Inserted at runtime').linkRecord(accountId).nextInChain().enqueue();
            Async.queueable(new AuditFinalizer()).attachFinalizer();
        }
    }

    public class AuditFinalizer extends QueueableJob.Finalizer {
        public override void work() {
        }
    }

    public class RelatedLinkingJob extends QueueableJob {
        public Id accountId;
        public RelatedLinkingJob(Id accountId) {
            this.accountId = accountId;
        }
        public override void work() {
            Async.linkRecords([SELECT Id FROM Contact WHERE AccountId = :accountId]);
            Async.linkRecords([SELECT Id FROM Opportunity WHERE AccountId = :accountId]);
        }
    }

    public class StopChainJob extends QueueableJob {
        public override void work() {
            Async.stopChain();
        }
    }

    public class SkipperJob extends QueueableJob {
        public String targetCustomJobId;
        public override void work() {
            Async.skipJob(targetCustomJobId);
        }
    }

    public class PageJob extends ChunkJob implements Async.ChunkResettable {
        public override void work(List<SObject> page) {
            Async.linkRecords(page);
            if (getRun().currentPageNumber() == 7) {
                throw new DemoException('UNABLE_TO_LOCK_ROW on page 7');
            }
        }
        public void resetBeforeNextChunk(Integer pageNumber) {
        }
    }

    public class FragilePageJob extends ChunkJob implements Async.ChunkResettable {
        public override void work(List<SObject> page) {
            if (getRun().currentPageNumber() == 3) {
                throw new DemoException('Validation failed: missing price on page 3');
            }
        }
        public void resetBeforeNextChunk(Integer pageNumber) {
        }
    }
}
