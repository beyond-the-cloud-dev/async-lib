/**
 * PMD False Positives:
 * - CognitiveComplexity: This was intended to have all the logic in one class
**/
@SuppressWarnings('PMD.CognitiveComplexity')
public inherited sharing class QueueableChain {
    @TestVisible
    private List<QueueableJob> jobs = new List<QueueableJob>();
    @TestVisible
    private Id initialQueuableChainSchedulableId;
    private Boolean isChainedContext = false;
    private Integer chainCounter = 0;
    private QueueableJob currentJob;

    @TestVisible
    private Map<String, QueueableJobSetting__mdt> queueableJobSettingByJobName {
        get {
            if (Test.isRunningTest()) {
                return queueableJobSettingByJobName ?? new Map<String, QueueableJobSetting__mdt>();
            }
            Map<String, QueueableJobSetting__mdt> jobSettings = new Map<String, QueueableJobSetting__mdt>();
            for (QueueableJobSetting__mdt jobSetting : QueueableJobSetting__mdt.getAll().values()) {
                jobSettings.put(jobSetting.QueueableJobName__c, jobSetting);
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
        currentJob.salesforceJobId = ctx.getJobId();
        currentJob.setChainCounterToName(++chainCounter);

        injectQueueableMockIfNeeded(currentJob);

        Savepoint sp = currentJob.rollbackOnJobExecuteFail ? Database.setSavepoint() : null;
        try {
            // Debug statements to determine the Job Id and Name
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
        
        createJobResultIfEnabled(previousJob);
        setFinalizerContextToAllFinalizersForPreviousJob(previousJob, ctx);
        enqueueNextJobIfAny();
    }

    public void createJobResultIfEnabled(QueueableJob previousJob) {
        if (queueableJobSettingByJobName.get(QueueableManager.QUEUEABLE_JOB_SETTING_ALL)?.CreateResult__c == true
            || queueableJobSettingByJobName.get(previousJob.className)?.CreateResult__c == true
        ) {
            previousJob.createAsyncResult();
        }
    }

    public void enqueueNextJobIfAny() {
        removeJobsThatAreDisabledAndDependentFinalizers();
        if (!hasNextJob() || (Test.isRunningTest() && System.isQueueable())) {
            return;
        }
        
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
        jobs.sort();
    }

    public List<QueueableJob> getJobs() {
        return jobs;
    }

    public void executeOrReplaceInitialQueueableChainSchedulableJob() {
        QueueableChainSchedulable.removeInitialQueuableChainSchedulableIfExists(initialQueuableChainSchedulableId);

        Datetime nextRunTime = Datetime.now().addMinutes(1);
        String hour = String.valueOf(nextRunTime.hour());
        String min = String.valueOf(nextRunTime.minute());
        String ss = String.valueOf(nextRunTime.second());
        String nextFireTime = ss + ' ' + min + ' ' + hour + ' * * ?';

        initialQueuableChainSchedulableId = System.schedule('QueueableChainSchedulable/' + String.valueOf(Datetime.now()) + '/' + UUID.randomUUID().toString(), nextFireTime, new QueueableChainSchedulable(this));
    }

    public QueueableJob getCurrentJob() {
        return currentJob;
    }

    public Boolean isChainedContext() {
        return isChainedContext;
    }

    public Id getQueueableChainSchedulableId() {
        return initialQueuableChainSchedulableId;
    }

    @TestVisible
    private void removeJobsThatAreDisabledAndDependentFinalizers() {
        Map<String, QueueableJobSetting__mdt> jobSettings = queueableJobSettingByJobName;

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
                injectFinalizerMockOrDefault(job, ctx);
            }
        }
    }

    private void injectQueueableMockIfNeeded(QueueableJob job) {
        if (Test.isRunningTest() && AsyncMock.hasQueueableMock(job.mockId)) {
            job.queueableCtx = AsyncMock.getQueueableContext(job.mockId);
        }
    }

    private void injectFinalizerMockOrDefault(QueueableJob job, FinalizerContext defaultCtx) {
        if (Test.isRunningTest() && AsyncMock.hasFinalizerMock(job.mockId)) {
            job.finalizerCtx = AsyncMock.getFinalizerContext(job.mockId);
            return;
        }
        job.finalizerCtx = defaultCtx;
    }
}
