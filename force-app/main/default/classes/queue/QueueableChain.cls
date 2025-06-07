public inherited sharing class QueueableChain {
    @TestVisible
    private List<QueueableJob> jobs = new List<QueueableJob>();
    @TestVisible
    private Id initialQueuableChainBatchJobId;
    private Boolean isChainedContext = false;
    private Integer chainCounter = 0;
    private QueueableJob currentJob;

    @TestVisible
    private Map<String, QueueableJobSetting__mdt> disabledQueueableJobSettingByJobName {
        get {
            if (Test.isRunningTest()) {
                return disabledQueueableJobSettingByJobName ?? new Map<String, QueueableJobSetting__mdt>();
            }
            Map<String, QueueableJobSetting__mdt> jobSettings = new Map<String, QueueableJobSetting__mdt>();
            for (QueueableJobSetting__mdt jobSetting : QueueableJobSetting__mdt.getAll().values()) {
                if (jobSetting.IsDisabled__c) {
                    jobSettings.put(jobSetting.QueueableJobName__c, jobSetting);
                }
            }
            return jobSettings;
        }
        private set;
    }

    public void execute(QueueableContext ctx) {
        QueueableManager.get().setChain(this);
        attachQueueableChainFinalizer();
        executeCurrentJob(ctx);
    }

    public void attachQueueableChainFinalizer() {
        System.attachFinalizer(new QueueableChainFinalizer(this));
    }

    public void executeCurrentJob(QueueableContext ctx) {
        if (!hasNextJob()) {
            return;
        }

        currentJob = getNextJobToProcess();
        currentJob.queueableCtx = ctx;
        currentJob.setChainCounterToName(++chainCounter);
        Savepoint sp = currentJob.rollbackOnJobExecuteFail ? Database.setSavepoint() : null;
        try {
            System.debug(currentJob.customJobId);
            System.debug(currentJob.uniqueName);
            currentJob.work();
        } catch (Exception ex) {
            if (!currentJob.continueOnJobExecuteFail) {
                throw ex;
            }
            if (currentJob.rollbackOnJobExecuteFail) {
                Database.rollback(sp);
                Database.releaseSavepoint(sp);
            }
        }
    }

    public void enqueueNextJobIfAnyFromFinalizer(FinalizerContext ctx) {
        QueueableJob previousJob = currentJob;
        previousJob.isProcessed = true;
        previousJob.finalizerCtx = ctx;
        
        setFinalizerContextToAllFinalizersForPreviousJob(previousJob, ctx);
        enqueueNextJobIfAny();
    }

    public void enqueueNextJobIfAny() {
        removeJobsThatAreDisabledAndDependentFinalizers();
        if (!hasNextJob() || (Test.isRunningTest() && System.isQueueable())) {
            return;
        }
        
        jobs.sort();
        QueueableJob nextJob = getNextJobToProcess();
        try {
            isChainedContext = true;
            nextJob.enqueue(this);
        } catch (Exception ex) {
            if (!nextJob.continueOnJobEnqueueFail) {
                throw ex;
            }
            isChainedContext = false;
            nextJob.isProcessed = true;
            enqueueNextJobIfAny();
        }
    }

    public Boolean hasNextJob() {
        return getNextJobToProcess() != null;
    }

    public void addJob(QueueableJob job) {
        job.setMainAttributes();
        jobs.add(job);
    }

    public void executeOrReplaceInitialQueueableChainBatchJobIfNotInChainContext() {
        if (isChainedContext) {
            return;
        }
        QueueableChainBatch.removeInitialQueuableChainBatchJobIfExists(initialQueuableChainBatchJobId);
        initialQueuableChainBatchJobId = Database.executeBatch(new QueueableChainBatch(this));
    }

    public QueueableJob getCurrentJob() {
        return currentJob;
    }

    public Boolean isChainedContext() {
        return isChainedContext;
    }

    public Id getQueueableChainBatchId() {
        return initialQueuableChainBatchJobId;
    }

    @TestVisible
    private void removeJobsThatAreDisabledAndDependentFinalizers() {
        Map<String, QueueableJobSetting__mdt> jobSettings = disabledQueueableJobSettingByJobName;

        if (jobSettings.isEmpty()) {
            // If there are no job settings, do not remove any jobs
            return;
        }

        QueueableJobSetting__mdt allJobSetting = jobSettings.get(QueueableManager.QUEUEABLE_JOB_SETTING_ALL);

        if(allJobSetting?.IsDisabled__c == true) {
            // If the global setting is disabled, clear all jobs
            jobs.clear();
            return;
        }

        // there are job settings, and if the class is disabled it should be removed and if there is a finalizer that have parentJobId set to this removed job, it should be removed as well, think about creating some logical way to do that, maybe recursion
        Set<String> customJobIdsToRemove = new Set<String>();
        for (QueueableJob job : jobs) {
            QueueableJobSetting__mdt jobSetting = jobSettings.get(job.className);
            if (jobSetting != null && jobSetting.IsDisabled__c) {
                customJobIdsToRemove.add(job.customJobId);
            }
        }

        // If there are no jobs to remove, return early
        if (customJobIdsToRemove.isEmpty()) {
            return;
        }
        customJobIdsToRemove = getAllCustomJobIdsToRemove(customJobIdsToRemove);
        
        for (Integer i = jobs.size() - 1; i >= 0; i--) {
            QueueableJob job = jobs[i];
            if (customJobIdsToRemove.contains(job.customJobId)) {
                jobs.remove(i);
            }
        }
    }

    private Set<String> getAllCustomJobIdsToRemove(Set<String> customJobIdsToRemove) {
        Set<String> dependentCustomJobIdsToRemove = new Set<String>();
        for (QueueableJob job : jobs) {
            if (customJobIdsToRemove.contains(job.parentCustomJobId)) {
                dependentCustomJobIdsToRemove.add(job.customJobId);
            }
        }
        
        if (dependentCustomJobIdsToRemove.isEmpty()) {
            return customJobIdsToRemove;
        } else {
            customJobIdsToRemove.addAll(getAllCustomJobIdsToRemove(dependentCustomJobIdsToRemove));
            return customJobIdsToRemove;
        }
    }

    private QueueableJob getNextJobToProcess() {
        for (QueueableJob job : jobs) {
            if (!job.isProcessed) {
                return job;
            }
        }
        return null;
    }

    private void setFinalizerContextToAllFinalizersForPreviousJob(QueueableJob previousJob, FinalizerContext ctx) {
        for (QueueableJob job : jobs) {
            if (!job.isProcessed && job.parentCustomJobId == previousJob.customJobId && job.finalizerCtx == null) {
                job.finalizerCtx = ctx;
            }
        }
    }
}
