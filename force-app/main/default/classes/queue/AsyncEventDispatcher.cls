/**
 * PMD False Positives:
 * - AvoidDebugStatements: a logger that cannot be reached leaves the debug log as the only channel
 * - ExcessiveParameterList: one event carries exactly one of the two context types, and bundling
 *   them into a wrapper would allocate an object per event for no gain
 **/
@SuppressWarnings('PMD.AvoidDebugStatements,PMD.ExcessiveParameterList')
public inherited sharing class AsyncEventDispatcher {
    private enum Event {
        ENQUEUED,
        SUCCEEDED,
        FAILED,
        RETRY_ENQUEUED
    }

    private static Set<String> alreadyWarnedClassNames = new Set<String>();

    public static void jobEnqueued(QueueableJob job, String loggerClassName) {
        dispatch(job, loggerClassName, Event.ENQUEUED, new Async.JobContext(job), null);
    }

    public static void jobSucceeded(QueueableJob job, String loggerClassName) {
        dispatch(job, loggerClassName, Event.SUCCEEDED, new Async.JobContext(job), null);
    }

    public static void jobFailed(QueueableJob job, String loggerClassName) {
        dispatch(job, loggerClassName, Event.FAILED, null, new Async.FailureContext(job));
    }

    public static void retryEnqueued(QueueableJob job, Integer delayMinutes, String loggerName) {
        Async.FailureContext ctx = new Async.FailureContext(job);
        ctx.nextAttemptDelayMinutes = delayMinutes;
        dispatch(job, loggerName, Event.RETRY_ENQUEUED, null, ctx);
    }

    private static void dispatch(
        QueueableJob job,
        String loggerClassName,
        Event firedEvent,
        Async.JobContext jobCtx,
        Async.FailureContext failureCtx
    ) {
        notifyListener(job, firedEvent, jobCtx, failureCtx);
        Object registeredLogger = newLogger(job, loggerClassName);
        if (registeredLogger != null) {
            notifyListener(registeredLogger, firedEvent, jobCtx, failureCtx);
        }
    }

    private static void notifyListener(
        Object listener,
        Event firedEvent,
        Async.JobContext jobCtx,
        Async.FailureContext failureCtx
    ) {
        try {
            switch on firedEvent {
                when ENQUEUED {
                    if (listener instanceof Async.OnJobEnqueued) {
                        ((Async.OnJobEnqueued) listener).onJobEnqueued(jobCtx);
                    }
                }
                when SUCCEEDED {
                    if (listener instanceof Async.OnJobSucceeded) {
                        ((Async.OnJobSucceeded) listener).onJobSucceeded(jobCtx);
                    }
                }
                when FAILED {
                    if (listener instanceof Async.OnJobFailed) {
                        ((Async.OnJobFailed) listener).onJobFailed(failureCtx);
                    }
                }
                when RETRY_ENQUEUED {
                    if (listener instanceof Async.OnRetryEnqueued) {
                        ((Async.OnRetryEnqueued) listener).onRetryEnqueued(failureCtx);
                    }
                }
            }
        } catch (Exception listenerFailure) {
            reportWithoutAffectingTheJob(listenerFailure);
        }
    }

    private static void reportWithoutAffectingTheJob(Exception listenerFailure) {
        System.debug(
            LoggingLevel.ERROR,
            String.format(
                QueueableManager.WARNING_LOGGER_THREW,
                new List<String>{
                    listenerFailure.getTypeName(),
                    listenerFailure.getMessage(),
                    listenerFailure.getStackTraceString()
                }
            )
        );
    }

    private static Object newLogger(QueueableJob job, String loggerClassName) {
        Object logger;
        try {
            logger = GlobalClassFactory.newInstance(loggerClassName);
        } catch (Exception instantiationFailure) {
            if (alreadyWarnedClassNames.add(loggerClassName)) {
                job.recordConfigurationWarning(
                    String.format(
                        QueueableManager.WARNING_LOGGER_NOT_USABLE,
                        new List<String>{ loggerClassName, instantiationFailure.getMessage() }
                    )
                );
            }
            return null;
        }
        if (
            logger == null &&
            String.isNotBlank(loggerClassName) &&
            alreadyWarnedClassNames.add(loggerClassName)
        ) {
            job.recordConfigurationWarning(
                String.format(
                    QueueableManager.WARNING_LOGGER_NOT_FOUND,
                    new List<String>{ loggerClassName, QueueableManager.API_PREFIX }
                )
            );
        }
        return logger;
    }
}
