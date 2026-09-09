/**
 * PMD False Positives:
 * - ExcessivePublicCount / TooManyFields: every field is part of the job contract
 * - CognitiveComplexity / CyclomaticComplexity: the base owns the whole retry lifecycle
 * - EmptyStatementBlock: the lifecycle hooks are no-op virtuals meant to be overridden
 **/
@SuppressWarnings(
    'PMD.ExcessivePublicCount,PMD.TooManyFields,PMD.CognitiveComplexity,PMD.CyclomaticComplexity,PMD.EmptyStatementBlock'
)
// A Queueable entry point with no sharing declaration runs in system mode. `inherited sharing`
// would resolve to `with sharing` here and change data visibility for every subclass.
public without sharing abstract class QueueableJob implements Queueable, Comparable {
    public Id salesforceJobId;
    public String customJobId;
    public String uniqueName;
    public Integer delay;
    public Integer priority;
    public AsyncOptions asyncOptions;
    public Boolean isProcessed = false;
    public Boolean continueOnJobEnqueueFail = false;
    public Boolean continueOnJobExecuteFail = false;
    public Boolean rollbackOnJobExecuteFail = false;
    public Boolean deepClone = false;
    public Boolean restoreStateOnRetry = false;
    public Boolean restoreStateOnNextChunk = false;
    public QueueableContext queueableCtx;

    public List<Async.Dependency> dependencies;
    public String chainId;
    public Integer chainSequence;
    public String skipStatus;
    public String skipReason;
    public Boolean resultCreated = false;

    public Integer maxRetries = 0;
    public Integer retryAttempt = 0;
    public Backoff backoff;
    public Set<String> retryOnExceptionTypes;
    public Boolean hasFailed = false;
    public FailureInfo failure;
    public Boolean retryDecision = false;
    public String retryHistory;

    public String parentCustomJobId;
    public FinalizerContext finalizerCtx;
    public String mockId;

    @TestVisible
    private QueueableChain chain;
    @TestVisible
    private QueueableJob enqueuedState;

    public transient String className {
        get {
            if (className == null) {
                className = getFullClassName(this);
            }
            return className;
        }
        private set;
    }

    public Boolean isFinalizer {
        get {
            return String.isNotBlank(parentCustomJobId);
        }
    }

    public abstract void work();

    public virtual Boolean isRetryable(Exception ex) {
        return true;
    }

    /**
     * Superseded by Async.Retryable.resetBeforeRetry(Integer). Nothing calls this any more.
     * It cannot be deleted: dropping a global member makes the package install fail in every
     * subscriber org that referenced it, before any of our code runs. See docs/api-evolution.md.
     **/
    public virtual void resetForRetry() {
    }

    protected virtual void clearFrameworkStateForCopy() {
    }

    protected virtual void carryFrameworkStateFrom(QueueableJob liveJob) {
    }

    public virtual void onFinalFailure(Async.FailureContext failureCtx) {
    }

    public void safeOnFinalFailure(Async.FailureContext failureCtx) {
        try {
            onFinalFailure(failureCtx);
        } catch (Exception hookEx) {
            appendRetryHistoryLine(
                'onFinalFailure() override threw ' +
                    hookEx.getTypeName() +
                    ': ' +
                    hookEx.getMessage()
            );
        }
    }

    public virtual QueueableJob cloneForDeepCopy() {
        String fullName = this.className;
        Type resolvedType = Type.forName(fullName);

        if (resolvedType == null && fullName.contains('.')) {
            resolvedType = Type.forName(
                fullName.substringBefore('.'),
                fullName.substringAfter('.')
            );
        }

        return (QueueableJob) JSON.deserialize(JSON.serialize(this), resolvedType);
    }

    public void execute(QueueableContext ctx) {
        chain.execute(ctx);
    }

    public Integer compareTo(Object compareTo) {
        QueueableJob compareToJob = (QueueableJob) compareTo;
        if (isFinalizer && !compareToJob.isFinalizer) {
            return -1;
        }
        if (!isFinalizer && compareToJob.isFinalizer) {
            return 1;
        }
        if (priority != null && compareToJob.priority == null) {
            return -1;
        }
        if (priority == null && compareToJob.priority != null) {
            return 1;
        }
        if (priority == compareToJob.priority) {
            return compareChainSequence(compareToJob);
        }
        return priority - compareToJob.priority;
    }

    // List.sort() does not define the order of equal elements, so equal priority needs an
    // explicit tiebreak to keep jobs running in the order they were chained.
    private Integer compareChainSequence(QueueableJob compareToJob) {
        return (chainSequence ?? 0) - (compareToJob.chainSequence ?? 0);
    }

    public void enqueue(QueueableChain chain) {
        this.chain = chain;
        if (delay != null) {
            salesforceJobId = System.enqueueJob(this, delay);
        } else if (asyncOptions != null) {
            salesforceJobId = System.enqueueJob(this, asyncOptions);
        } else {
            salesforceJobId = System.enqueueJob(this);
        }
    }

    public void setMainAttributes() {
        this.customJobId = UUID.randomUUID().toString();
        this.uniqueName = className + '::' + System.now().formatGMT('yyyy-MM-dd\'T\'HH:mm:ss.SSSZ');
    }

    public void setChainCounterToName(Integer chainCounter) {
        this.uniqueName = this.uniqueName + '::' + String.valueOf(chainCounter);
    }

    public Boolean canRetry() {
        return hasFailed && retryAttempt < maxRetries && retryDecision;
    }

    public void recordFailure(Exception ex) {
        this.hasFailed = true;
        this.failure = new FailureInfo(ex.getTypeName(), ex.getMessage());
        this.failure.stackTrace = ex.getStackTraceString();
        Boolean typeIsRetryable = matchesRetryOnTypes(ex.getTypeName());
        if (!typeIsRetryable && maxRetries > 0) {
            appendRetryHistoryLine(
                ex.getTypeName() +
                    ' is not in retryOn(' +
                    String.join(new List<String>(retryOnExceptionTypes), ', ') +
                    ') - not retried'
            );
        }
        this.retryDecision = typeIsRetryable && safeIsRetryable(ex);
    }

    public void recordUnknownFailure() {
        this.hasFailed = true;
        // No exception object to classify: retry only when no type restriction was set.
        this.retryDecision = retryOnExceptionTypes == null || retryOnExceptionTypes.isEmpty();
    }

    public Boolean matchesRetryOnTypes(String typeName) {
        if (String.isBlank(typeName)) {
            return false;
        }
        if (retryOnExceptionTypes == null || retryOnExceptionTypes.isEmpty()) {
            return true;
        }
        for (String allowedType : retryOnExceptionTypes) {
            if (
                typeName.equalsIgnoreCase(allowedType) ||
                typeName.endsWithIgnoreCase('.' + allowedType)
            ) {
                return true;
            }
        }
        return false;
    }

    public Boolean safeIsRetryable(Exception ex) {
        try {
            return isRetryable(ex);
        } catch (Exception overrideEx) {
            appendRetryHistoryLine(
                'isRetryable() override threw ' +
                    overrideEx.getTypeName() +
                    ': ' +
                    overrideEx.getMessage() +
                    ' — not retried'
            );
            return false;
        }
    }

    public void recordRetryHistory(Integer attemptNumber, Integer delayMinutes) {
        String cause = failure != null
            ? failure.type + ' - ' + failure.message
            : 'exception unavailable';
        appendRetryHistoryLine(
            'Attempt ' +
                attemptNumber +
                ': ' +
                cause +
                (delayMinutes != null ? ' (retry in ' + delayMinutes + 'm)' : ' (no further retry)')
        );
    }

    private void appendRetryHistoryLine(String line) {
        retryHistory = String.isBlank(retryHistory) ? line : retryHistory + '\n' + line;
    }

    public QueueableJob cloneJob() {
        if (deepClone) {
            try {
                return deepCloneWithoutRuntimeState();
            } catch (Exception cloneFailure) {
                throw new IllegalArgumentException(
                    'deepClone() failed for the job "' +
                        className +
                        '": ' +
                        causeAndRemedy(cloneFailure)
                );
            }
        }
        return this.clone();
    }

    public void captureEnqueuedState() {
        Boolean retryWillRestore = restoreStateOnRetry && maxRetries > 0;
        Boolean pagingWillRestore = restoreStateOnNextChunk && this instanceof ChunkJob;
        if (!retryWillRestore && !pagingWillRestore) {
            return;
        }
        try {
            enqueuedState = deepCloneWithoutRuntimeState();
        } catch (Exception captureFailure) {
            throw new IllegalArgumentException(
                'restoreStateOnRetry() and restoreStateOnNextChunk() replay the job from a deep ' +
                    'copy taken at enqueue, and the job "' +
                    className +
                    '" cannot be copied: ' +
                    causeAndRemedy(captureFailure) +
                    '\nOr drop the option and clear your own state in resetBeforeRetry(Integer) ' +
                    'or resetBeforeNextChunk(Integer) instead.'
            );
        }
    }

    public Boolean canRestoreEnqueuedState() {
        return enqueuedState != null;
    }

    // Only the fields the subclass declared come back. Everything QueueableJob and ChunkJob own
    // is progression the caller re-applies from the live job.
    public QueueableJob restoreEnqueuedState() {
        QueueableJob restored = enqueuedState.deepCloneWithoutRuntimeState();
        restored.enqueuedState = enqueuedState;
        restored.restoreStateOnRetry = restoreStateOnRetry;
        restored.restoreStateOnNextChunk = restoreStateOnNextChunk;
        restored.retryHistory = retryHistory;
        restored.carryFrameworkStateFrom(this);
        return restored;
    }

    /**
     * JSON cannot round-trip a live job, for three unrelated reasons:
     * - `chain` points back at this job: "Cycle detected"
     * - `queueableCtx` / `finalizerCtx` are platform interfaces: "Cannot deserialize JSON as
     *   abstract type"
     * - `backoff` / `dependencies` / `failure` are Async Lib types, and JSON.serialize refuses any
     *   graph crossing a namespace, so a subscriber's override hits "Type cannot be serialized"
     * Stripping a shallow copy rather than this job also covers subclass overrides.
     **/
    private QueueableJob deepCloneWithoutRuntimeState() {
        QueueableJob stripped = this.clone();
        stripped.chain = null;
        stripped.queueableCtx = null;
        stripped.finalizerCtx = null;
        stripped.backoff = null;
        stripped.dependencies = null;
        stripped.failure = null;
        stripped.enqueuedState = null;
        stripped.clearFrameworkStateForCopy();

        QueueableJob copy = stripped.cloneForDeepCopy();
        // Backoff is immutable so sharing is safe. The other two are not, and sharing them
        // would defeat the isolation deepClone() exists to provide.
        copy.backoff = this.backoff;
        copy.dependencies = deepCopyOf(this.dependencies);
        copy.failure = deepCopyOf(this.failure);
        return copy;
    }

    // Every cause is a different mistake with a different fix, so the message has to name the
    // right one. The two JSONException causes are only separable by their platform wording, which
    // shouldStillSeeThePlatformWordingDeepCloneGuidanceBranchesOn() guards against changing.
    private String causeAndRemedy(Exception cloneFailure) {
        String remedy;
        if (cloneFailure instanceof TypeException) {
            remedy =
                'The job has a field typed as an interface or abstract class, which JSON cannot ' +
                'rebuild. Mark that field transient, or hold a concrete type instead.';
        } else if (cloneFailure.getMessage().contains('Cycle detected')) {
            remedy =
                'The job holds a reference back to itself. Break the cycle, or mark the ' +
                'offending field transient.';
        } else if (cloneFailure.getMessage().contains('Type cannot be serialized')) {
            remedy =
                'Async Lib is installed as a namespaced package, so it cannot serialize your ' +
                'class. Extend BaseQueueableJob, or override cloneForDeepCopy() on this job. See ' +
                QueueableManager.DOCS_URL +
                '/explanations/deep-clone-in-packages';
        } else {
            remedy = 'See ' + QueueableManager.DOCS_URL + '/explanations/job-cloning';
        }
        return cloneFailure.getTypeName() + ': ' + cloneFailure.getMessage() + '\n' + remedy;
    }

    // Same namespace as these types, so never blocked by the boundary a subscriber hits.
    private List<Async.Dependency> deepCopyOf(List<Async.Dependency> dependencies) {
        return dependencies == null
            ? null
            : (List<Async.Dependency>) JSON.deserialize(
                  JSON.serialize(dependencies),
                  List<Async.Dependency>.class
              );
    }

    private FailureInfo deepCopyOf(FailureInfo failure) {
        return failure == null
            ? null
            : (FailureInfo) JSON.deserialize(JSON.serialize(failure), FailureInfo.class);
    }

    public void recordRetryNotEnqueued(Integer attemptNumber, Exception ex) {
        appendRetryHistoryLine(
            'Attempt ' +
                attemptNumber +
                ' could not be enqueued: ' +
                ex.getTypeName() +
                ': ' +
                ex.getMessage()
        );
    }

    private String getFullClassName(Object job) {
        String result;
        try {
            // A failed cast is the only way to read the runtime type with its namespace.
            String.valueOf((DateTime) job);
        } catch (System.TypeException expectedTypeException) {
            String message = expectedTypeException.getMessage()
                .substringAfter('Invalid conversion from runtime type ');
            result = message.substringBefore(' to Datetime');
        }
        return result;
    }

    @JsonAccess(serializable='always' deserializable='always')
    public class FailureInfo {
        public String type;
        public String message;
        public String stackTrace;

        public FailureInfo(String type, String message) {
            this.type = type;
            this.message = message;
        }
    }

    public abstract class AllowsCallouts extends QueueableJob implements Database.AllowsCallouts {
    }

    public abstract class Finalizer extends AllowsCallouts {
    }
}
