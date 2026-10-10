/**
 * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
 *
 * v3.1.0
 *
 * PMD False Positives:
 * - ApexSOQLInjection: the query is built from field paths checked against FIELD_PATH and an
 *   object name read from the failed record ids, never from free text
 **/
@SuppressWarnings('PMD.ApexSOQLInjection')
// The original batch could see the records that failed. `without sharing` reloads the same
// records whoever starts the requeue, instead of quietly dropping the ones that user cannot see.
public without sharing class BatchFieldReload implements Async.BatchRecordLoader {
    private static final String ID_FIELD = 'Id';
    private static final Pattern FIELD_PATH = Pattern.compile(
        '^[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z][A-Za-z0-9_]*)*$'
    );

    private List<String> fieldPaths = new List<String>{ ID_FIELD };

    public BatchFieldReload(List<String> requestedPaths) {
        for (String path : requestedPaths) {
            if (path == null || !FIELD_PATH.matcher(path).matches()) {
                throw new Async.IllegalArgumentException(
                    String.format(
                        QueueableManager.ERROR_MESSAGE_INVALID_RELOAD_FIELD,
                        new List<String>{ path, QueueableManager.API_PREFIX }
                    )
                );
            }
            if (!path.equalsIgnoreCase(ID_FIELD)) {
                fieldPaths.add(path);
            }
        }
    }

    public List<SObject> load(Set<Id> failedRecordIds) {
        return reload(failedRecordIds);
    }

    public void assertQueryIsValidFor(Id sampleRecordId) {
        Set<Id> sample = new Set<Id>{ sampleRecordId };
        try {
            reload(sample);
        } catch (QueryException invalidQuery) {
            throw new Async.IllegalArgumentException(
                String.format(
                    QueueableManager.ERROR_MESSAGE_RELOAD_QUERY_INVALID,
                    new List<String>{ queryFor(sample), invalidQuery.getMessage() }
                )
            );
        }
    }

    private List<SObject> reload(Set<Id> failedRecordIds) {
        return Database.queryWithBinds(
            queryFor(failedRecordIds),
            new Map<String, Object>{ 'failedRecordIds' => failedRecordIds },
            AccessLevel.SYSTEM_MODE
        );
    }

    private String queryFor(Set<Id> failedRecordIds) {
        return 'SELECT ' +
            String.join(fieldPaths, ', ') +
            ' FROM ' +
            objectOf(failedRecordIds) +
            ' WHERE Id IN :failedRecordIds';
    }

    private SObjectType objectOf(Set<Id> failedRecordIds) {
        Set<SObjectType> types = new Set<SObjectType>();
        for (Id recordId : failedRecordIds) {
            types.add(recordId.getSObjectType());
        }
        if (types.size() != 1) {
            throw new Async.IllegalArgumentException(
                String.format(
                    QueueableManager.ERROR_MESSAGE_RELOAD_MIXED_TYPES,
                    new List<String>{ QueueableManager.API_PREFIX }
                )
            );
        }
        return new List<SObjectType>(types)[0];
    }
}
