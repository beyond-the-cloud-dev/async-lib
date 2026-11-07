/**
 * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
 *
 * v3.2.0
 **/
public with sharing class AsyncJobTimelineNames {
    private static final Integer MAX_NAME_LOOKUP_TYPES = 10;

    public static Map<Id, String> of(Set<Id> recordIds) {
        Map<Id, String> nameById = new Map<Id, String>();
        Map<Schema.SObjectType, Set<Id>> idsByType = new Map<Schema.SObjectType, Set<Id>>();
        for (Id recordId : recordIds) {
            Schema.SObjectType type = QueueableManager.sobjectTypeOrNull(recordId);
            if (type == null) {
                continue;
            }
            Set<Id> ids = idsByType.get(type) ?? new Set<Id>();
            ids.add(recordId);
            idsByType.put(type, ids);
        }
        Integer typesLookedUp = 0;
        for (Schema.SObjectType type : idsByType.keySet()) {
            if (typesLookedUp++ >= MAX_NAME_LOOKUP_TYPES) {
                break;
            }
            nameById.putAll(readableNamesOfOneType(type, idsByType.get(type)));
        }
        return nameById;
    }

    private static Map<Id, String> readableNamesOfOneType(Schema.SObjectType type, Set<Id> ids) {
        Map<Id, String> nameById = new Map<Id, String>();
        String nameField = nameFieldOf(type);
        if (nameField == null) {
            return nameById;
        }
        try {
            for (
                SObject record : Database.queryWithBinds(
                    'SELECT Id, ' +
                        nameField +
                        ' FROM ' +
                        type.getDescribe().getName() +
                        ' WHERE Id IN :ids',
                    new Map<String, Object>{ 'ids' => ids },
                    AccessLevel.USER_MODE
                )
            ) {
                nameById.put(record.Id, String.valueOf(record.get(nameField)));
            }
        } catch (QueryException viewerCannotReadObject) {
            return nameById;
        }
        return nameById;
    }

    private static String nameFieldOf(Schema.SObjectType type) {
        for (Schema.SObjectField field : type.getDescribe().fields.getMap().values()) {
            Schema.DescribeFieldResult describe = field.getDescribe();
            if (describe.isNameField()) {
                return describe.getName();
            }
        }
        return null;
    }
}
