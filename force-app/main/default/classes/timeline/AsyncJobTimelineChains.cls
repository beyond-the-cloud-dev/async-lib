/**
 * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
 *
 * v3.2.0
 **/
public with sharing class AsyncJobTimelineChains {
    private static final Integer LINK_SCAN_LIMIT = 2000;
    private static final Datetime ALL_TIME = Datetime.newInstance(1970, 1, 1);
    private static final String STATUS_INFLIGHT = 'inflight';
    private static final String STATUS_FAILED = 'failed';
    private static final String STATUS_COMPLETED = 'completed';
    private static final Map<String, Integer> CARD_PRECEDENCE = new Map<String, Integer>{
        STATUS_INFLIGHT => 0,
        STATUS_FAILED => 1,
        STATUS_COMPLETED => 2
    };
    private static final Set<String> FAILED_ROW_STATUSES = new Set<String>{
        QueueableManager.STATUS_FAILED,
        QueueableManager.STATUS_FRAMEWORK_ERROR,
        QueueableManager.STATUS_SKIPPED_CHAIN_STOPPED
    };

    private final Id recordId;
    private final Datetime cutoff;
    private final List<ChainOrder> chains;

    public AsyncJobTimelineChains(Id recordId, Integer daysBack) {
        this.recordId = recordId;
        this.cutoff = daysBack <= 0 ? ALL_TIME : System.now().addDays(-daysBack);
        this.chains = newestFirst(recordId, cutoff);
    }

    private static List<ChainOrder> newestFirst(Id recordId, Datetime cutoff) {
        List<ChainOrder> chains = new List<ChainOrder>();
        for (AggregateResult chain : [
            SELECT ChainId__c chainId, MIN(CreatedDate) started, MIN(Name) firstResult
            FROM AsyncResult__c
            WHERE
                ChainId__c != NULL
                AND CreatedDate >= :cutoff
                AND Id IN (
                    SELECT AsyncResult__c
                    FROM AsyncResultLink__c
                    WHERE Key__c = :recordId AND Source__c = :QueueableManager.SOURCE_SALESFORCE
                )
            WITH USER_MODE
            GROUP BY ChainId__c
            LIMIT :LINK_SCAN_LIMIT
        ]) {
            chains.add(new ChainOrder(chain));
        }
        addStatusFromAllRows(chains);
        chains.sort();
        return chains;
    }

    private static void addStatusFromAllRows(List<ChainOrder> chains) {
        Map<String, ChainOrder> chainById = new Map<String, ChainOrder>();
        for (ChainOrder chain : chains) {
            chainById.put(chain.chainId, chain);
        }
        for (AggregateResult row : [
            SELECT ChainId__c chainId, Status__c status
            FROM AsyncResult__c
            WHERE ChainId__c IN :chainById.keySet()
            WITH USER_MODE
            GROUP BY ChainId__c, Status__c
        ]) {
            chainById.get((String) row.get('chainId'))
                .absorb(chainStatusFor((String) row.get('status')));
        }
    }

    private static String chainStatusFor(String rowStatus) {
        if (rowStatus == QueueableManager.STATUS_ENQUEUED) {
            return STATUS_INFLIGHT;
        }
        if (FAILED_ROW_STATUSES.contains(rowStatus)) {
            return STATUS_FAILED;
        }
        return STATUS_COMPLETED;
    }

    private static Integer cardPrecedenceOf(String chainStatus) {
        return CARD_PRECEDENCE.get(chainStatus);
    }

    public List<String> idsMatching(String statusFilter, List<String> keepChainIds) {
        Set<String> kept = new Set<String>(keepChainIds ?? new List<String>());
        List<String> chainIds = new List<String>();
        for (ChainOrder chain : chains) {
            if (
                String.isBlank(statusFilter) ||
                statusFilter == 'all' ||
                chain.status == statusFilter ||
                kept.contains(chain.chainId)
            ) {
                chainIds.add(chain.chainId);
            }
        }
        return chainIds;
    }

    public void refreshFrom(List<AsyncResult__c> rows) {
        Map<String, ChainOrder> chainById = new Map<String, ChainOrder>();
        for (ChainOrder chain : chains) {
            chainById.put(chain.chainId, chain);
        }
        Set<String> refreshed = new Set<String>();
        for (AsyncResult__c row : rows) {
            ChainOrder chain = chainById.get(row.ChainId__c);
            if (chain == null) {
                continue;
            }
            if (refreshed.add(chain.chainId)) {
                chain.status = STATUS_COMPLETED;
            }
            chain.absorb(chainStatusFor(row.Status__c));
        }
    }

    public Map<String, Integer> counts() {
        Map<String, Integer> counts = new Map<String, Integer>{
            'all' => chains.size(),
            STATUS_INFLIGHT => 0,
            STATUS_FAILED => 0,
            STATUS_COMPLETED => 0
        };
        for (ChainOrder chain : chains) {
            counts.put(chain.status, counts.get(chain.status) + 1);
        }
        return counts;
    }

    private class ChainOrder implements Comparable {
        public String chainId;
        public Datetime started;
        public String firstResult;
        public String status = STATUS_COMPLETED;

        public ChainOrder(AggregateResult chain) {
            chainId = (String) chain.get('chainId');
            started = (Datetime) chain.get('started');
            firstResult = (String) chain.get('firstResult') ?? '';
        }

        public void absorb(String rowStatus) {
            if (cardPrecedenceOf(rowStatus) < cardPrecedenceOf(status)) {
                status = rowStatus;
            }
        }

        public Integer compareTo(Object other) {
            ChainOrder that = (ChainOrder) other;
            if (started != that.started) {
                return started > that.started ? -1 : 1;
            }
            return that.firstResult.compareTo(firstResult);
        }
    }

    public Integer olderCount() {
        Set<String> older = new Set<String>();
        for (AsyncResultLink__c link : [
            SELECT AsyncResult__r.ChainId__c
            FROM AsyncResultLink__c
            WHERE
                Key__c = :recordId
                AND Source__c = :QueueableManager.SOURCE_SALESFORCE
                AND AsyncResult__r.CreatedDate < :cutoff
            WITH USER_MODE
            LIMIT :LINK_SCAN_LIMIT
        ]) {
            older.add(link.AsyncResult__r.ChainId__c);
        }
        return older.size();
    }

    public static List<String> slice(List<String> chainIds, Integer offset, Integer count) {
        List<String> page = new List<String>();
        for (Integer i = offset; i < Math.min(chainIds.size(), offset + count); i++) {
            page.add(chainIds[i]);
        }
        return page;
    }
}
