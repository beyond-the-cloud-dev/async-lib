/**
 * JSON cannot cross a namespace boundary in either direction, so on a packaged install both
 * conversions run in the subscriber's own code through a registered Async.JobSerializer. A source
 * deployment has no boundary and needs no registration.
 **/
public inherited sharing class JobPayload {
    public static final Integer MAX_CHARS = 131072;

    public static String forJob(QueueableJob job) {
        QueueableJob storable = job.copyWithoutRuntimeState();
        Async.JobSerializer serializer = registeredSerializer(job.className);
        return serializer == null ? JSON.serialize(storable) : serializer.serialize(storable);
    }

    public static QueueableJob toJob(String className, String payload) {
        Async.JobSerializer serializer = registeredSerializer(className);
        if (serializer != null) {
            return serializer.deserialize(className, payload);
        }
        Type jobType = resolveType(className);
        return jobType == null ? null : (QueueableJob) JSON.deserialize(payload, jobType);
    }

    public static Type resolveType(String fullName) {
        return Type.forName(fullName) ?? resolveTypeInsideNamespace(fullName);
    }

    private static Type resolveTypeInsideNamespace(String fullName) {
        return fullName.contains('.')
            ? Type.forName(fullName.substringBefore('.'), fullName.substringAfter('.'))
            : null;
    }

    private static Async.JobSerializer registeredSerializer(String jobClassName) {
        String serializerClassName = QueueableManager.settingFor(
            jobClassName,
            QueueableJobSetting__mdt.JobSerializerClass__c
        );
        if (String.isBlank(serializerClassName)) {
            return null;
        }
        Object serializer = GlobalClassFactory.newInstance(serializerClassName);
        if (!(serializer instanceof Async.JobSerializer)) {
            throw new Async.IllegalArgumentException(
                String.format(
                    QueueableManager.ERROR_MESSAGE_SERIALIZER_NOT_USABLE,
                    new List<String>{ serializerClassName, QueueableManager.API_PREFIX }
                )
            );
        }
        return (Async.JobSerializer) serializer;
    }
}
