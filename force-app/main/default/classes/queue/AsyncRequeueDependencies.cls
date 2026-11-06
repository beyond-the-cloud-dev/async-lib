/**
 * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
 *
 * v3.1.0
 **/
public inherited sharing class AsyncRequeueDependencies {
    private final Async.RequeueSummary summary;
    private final Map<String, String> newCustomJobIdByOld = new Map<String, String>();
    private final Map<String, AsyncResult__c> targetByKey;

    public AsyncRequeueDependencies(List<AsyncResult__c> rows, Async.RequeueSummary summary) {
        this.summary = summary;
        this.targetByKey = targetsOf(rows);
    }

    public void remember(String oldCustomJobId, String newCustomJobId) {
        newCustomJobIdByOld.put(oldCustomJobId, newCustomJobId);
    }

    public List<Async.Dependency> rebuiltFor(AsyncResult__c row) {
        List<Async.Dependency> rebuilt = new List<Async.Dependency>();
        for (Async.Dependency dependency : storedDependenciesOf(row)) {
            String replayTarget = newCustomJobIdByOld.get(dependency.resolvedTargetCustomJobId);
            if (replayTarget != null) {
                dependency.resolvedTargetCustomJobId = replayTarget;
                rebuilt.add(dependency);
            } else if (!resolvedAgainstHistory(row, dependency)) {
                return null;
            }
        }
        return rebuilt;
    }

    private Boolean resolvedAgainstHistory(AsyncResult__c row, Async.Dependency dependency) {
        String oldTargetId = dependency.resolvedTargetCustomJobId;
        AsyncResult__c target = targetByKey.get(targetKey(row.ChainId__c, oldTargetId));
        if (target == null) {
            skip(
                row,
                QueueableManager.REQUEUE_SKIPPED_DEPENDENCY_UNKNOWN,
                new List<String>{ oldTargetId }
            );
            return false;
        }
        Async.Outcome actual = QueueableManager.outcomeOf(target.Status__c);
        String label = target.JobName__c ?? target.ClassName__c;
        if (!QueueableManager.outcomeMatches(actual, dependency.requiredOutcome)) {
            skip(
                row,
                QueueableManager.REQUEUE_SKIPPED_DEPENDENCY_UNMET,
                new List<String>{
                    label,
                    dependency.requiredOutcome.name(),
                    actual?.name() ?? 'NOT_RUN'
                }
            );
            return false;
        }
        noteDropped(
            row.Id,
            String.format(
                QueueableManager.REQUEUE_DEPENDENCY_DROPPED,
                new List<String>{ label, actual.name() }
            )
        );
        return true;
    }

    private void skip(AsyncResult__c row, String message, List<String> arguments) {
        summary.skipReasonByResultId.put(row.Id, String.format(message, arguments));
    }

    private void noteDropped(Id resultId, String note) {
        String earlier = summary.droppedDependencyByResultId.get(resultId);
        summary.droppedDependencyByResultId.put(
            resultId,
            earlier == null ? note : earlier + '\n' + note
        );
    }

    public static List<Async.Dependency> storedDependenciesOf(AsyncResult__c row) {
        return String.isBlank(row.Dependencies__c)
            ? new List<Async.Dependency>()
            : (List<Async.Dependency>) JSON.deserialize(
                  row.Dependencies__c,
                  List<Async.Dependency>.class
              );
    }

    private static Map<String, AsyncResult__c> targetsOf(List<AsyncResult__c> rows) {
        Set<String> chainIds = new Set<String>();
        Set<String> targetIds = new Set<String>();
        for (AsyncResult__c row : rows) {
            for (Async.Dependency dependency : storedDependenciesOf(row)) {
                chainIds.add(row.ChainId__c);
                targetIds.add(dependency.resolvedTargetCustomJobId);
            }
        }
        Map<String, AsyncResult__c> targetByKey = new Map<String, AsyncResult__c>();
        if (targetIds.isEmpty()) {
            return targetByKey;
        }
        for (AsyncResult__c target : [
            SELECT ChainId__c, CustomJobId__c, Status__c, JobName__c, ClassName__c
            FROM AsyncResult__c
            WHERE ChainId__c IN :chainIds AND CustomJobId__c IN :targetIds
            WITH SYSTEM_MODE
        ]) {
            targetByKey.put(targetKey(target.ChainId__c, target.CustomJobId__c), target);
        }
        return targetByKey;
    }

    private static String targetKey(String chainId, String customJobId) {
        return chainId + '|' + customJobId;
    }
}
