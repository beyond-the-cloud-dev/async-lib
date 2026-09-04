@SuppressWarnings('PMD.ExcessivePublicCount')
public abstract class QueueableJob implements Queueable, Comparable {
    public Id salesforceJobId;
    public String customJobId;
    public transient String className {
        get {
            if (className == null) {
                className = getFullClassName(this);
            }
            return className;
        }
        private set;
    }
    public String uniqueName;
    public Integer delay;
    public Integer priority;
    public AsyncOptions asyncOptions;
    public Boolean isProcessed = false;
    public Boolean continueOnJobEnqueueFail = false;
    public Boolean continueOnJobExecuteFail = false;
    public Boolean rollbackOnJobExecuteFail = false;
    public Boolean deepClone = false;
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
    public Boolean isFinalizer {
        get {
            return String.isNotBlank(parentCustomJobId);
        }
    }

    private QueueableChain chain;

    public abstract void work();

    public virtual Boolean isRetryable(Exception ex) {
        return true;
    }

    public virtual void resetForRetry() {
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
        this.retryDecision = matchesRetryOnTypes(ex.getTypeName()) && safeIsRetryable(ex);
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
                return cloneForDeepCopy();
            } catch (JSONException e) {
                throw new IllegalArgumentException(
                    'deepClone() failed for the job "' +
                        className +
                        '". ' +
                        'When using a namespaced package, override cloneForDeepCopy() in your QueueableJob subclass: ' +
                        'public override QueueableJob cloneForDeepCopy() { ' +
                        'return (QueueableJob) JSON.deserialize(JSON.serialize(this), YourClassName.class); }'
                );
            }
        }
        return this.clone();
    }

    private String getFullClassName(Object job) {
        String result;
        try {
            // A failed cast is the only way to read the runtime type with its namespace
            String.valueOf((DateTime) job);
        } catch (System.TypeException expectedTypeException) {
            String message = expectedTypeException.getMessage()
                .substringAfter('Invalid conversion from runtime type ');
            result = message.substringBefore(' to Datetime');
        }
        return result;
    }

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
