/**
 * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
 *
 * v3.1.0
 *
 * PMD False Positives:
 * - ApexAssertionsShouldIncludeMessage: not every assertion needs a message
 * - ExcessiveParameterList: the seed helpers take the row shape as arguments
 * - EmptyStatementBlock: a queueable that does nothing is the fixture
 * - CyclomaticComplexity: flat tests, the class total only counts how many there are
 **/
@SuppressWarnings(
    'PMD.ApexAssertionsShouldIncludeMessage,PMD.ExcessiveParameterList,PMD.EmptyStatementBlock,PMD.CyclomaticComplexity'
)
@IsTest
private class AsyncJobTimelineControllerTest {
    private static final String RESULT_ACCESS = 'AsyncResultAccess';
    private static final String REQUEUE_ACCESS = 'AsyncRequeueAccess';
    private static final String OPERATOR_ALIAS = 'tlop';

    @TestSetup
    private static void createOperator() {
        userWith(OPERATOR_ALIAS, new List<String>{ RESULT_ACCESS, REQUEUE_ACCESS });
    }

    @IsTest
    private static void shouldLoadSequencesNewestFirstWithinTheWindow() {
        Account order = new Account(Name = 'Order');
        insert order;
        seedChain(order, 'recent', 'Recent run', 2, System.now().addHours(-1));
        seedChain(order, 'earlier', 'Earlier run', 3, System.now().addDays(-2));
        seedChain(order, 'old', 'Old run', 1, System.now().addDays(-10));

        AsyncJobTimelineController.TimelinePage page = loadAsOperator(order.Id, 7, 10, 0);

        Assert.areEqual(2, page.sequences.size(), 'The 10-day-old chain is outside the window.');
        Assert.areEqual('recent', page.sequences[0].chainId);
        Assert.areEqual('Recent run', page.sequences[0].name);
        Assert.areEqual('earlier', page.sequences[1].chainId);
        Assert.areEqual(3, page.sequences[1].steps.size());
        Assert.areEqual(1, page.sequences[1].steps[0].chainSequence);
        Assert.areEqual(3, page.sequences[1].steps[2].chainSequence);
        Assert.areEqual(1, page.olderChainCount);
        Assert.isFalse(page.hasMore);
        Assert.isNotNull(page.fingerprint);
        Assert.areEqual('Order', page.sequences[0].steps[0].records[0].name);
        Assert.areEqual('Account', page.sequences[0].steps[0].records[0].objectName);
    }

    @IsTest
    private static void shouldNotLiftARunningChainAboveNewerOnes() {
        Account order = new Account(Name = 'Order');
        insert order;
        seedChain(order, 'newer', 'Newer run', 1, System.now().addHours(-1));
        seedChain(order, 'older', 'Older run', 1, System.now().addDays(-2));
        List<AsyncResult__c> live = seedChain(
            order,
            'live',
            'Live run',
            2,
            System.now().addDays(-5)
        );
        live[1].Status__c = QueueableManager.STATUS_ENQUEUED;
        update live[1];

        AsyncJobTimelineController.TimelinePage page = loadAsOperator(order.Id, 7, 10, 0);

        Assert.areEqual(new List<String>{ 'newer', 'older', 'live' }, chainIdsOf(page));
        Assert.areEqual(3, page.totalChainCount);
    }

    @IsTest
    private static void shouldNotMoveAChainWhenItFinishes() {
        Account order = new Account(Name = 'Order');
        insert order;
        List<AsyncResult__c> recent = seedChain(
            order,
            'recent',
            'Recent run',
            1,
            System.now().addHours(-1)
        );
        List<AsyncResult__c> late = seedChain(
            order,
            'late',
            'Started early, finished last',
            2,
            System.now().addDays(-2)
        );
        recent[0].FinishedAt__c = System.now().addHours(-1);
        late[1].FinishedAt__c = System.now();
        update new List<AsyncResult__c>{ recent[0], late[1] };

        AsyncJobTimelineController.TimelinePage page = loadAsOperator(order.Id, 7, 10, 0);

        Assert.areEqual(new List<String>{ 'recent', 'late' }, chainIdsOf(page));
    }

    @IsTest
    private static void shouldKeepAWatchedChainInTheFilterAfterItFinishes() {
        Account order = new Account(Name = 'Order');
        insert order;
        seedChain(order, 'watched', 'Finished while watched', 1, System.now().addHours(-1));
        seedChain(order, 'other', 'Finished earlier', 1, System.now().addHours(-2));
        List<AsyncResult__c> live = seedChain(
            order,
            'live',
            'Live run',
            2,
            System.now().addHours(-3)
        );
        live[1].Status__c = QueueableManager.STATUS_ENQUEUED;
        update live[1];

        AsyncJobTimelineController.TimelinePage page = loadInFlightKeeping(
            order.Id,
            new List<String>{ 'watched' }
        );

        Assert.areEqual(new List<String>{ 'watched', 'live' }, chainIdsOf(page));
        Assert.areEqual(2, page.totalChainCount);
        Assert.areEqual(1, page.counts.get('inflight'), 'The chip counts what still runs.');
    }

    @IsTest
    private static void shouldNotShowAKeptChainTheRecordIsNotLinkedTo() {
        Account order = new Account(Name = 'Order');
        Account stranger = new Account(Name = 'Stranger');
        insert new List<Account>{ order, stranger };
        seedChain(stranger, 'foreign', 'Linked elsewhere', 1, System.now().addHours(-1));
        seedChain(order, 'own', 'Own run', 1, System.now().addHours(-2));

        AsyncJobTimelineController.TimelinePage page = loadInFlightKeeping(
            order.Id,
            new List<String>{ 'foreign' }
        );

        Assert.areEqual(new List<String>(), chainIdsOf(page));
    }

    @IsTest
    private static void shouldKeepEnqueueOrderForChainsStartedInTheSameSecond() {
        Account order = new Account(Name = 'Order');
        insert order;
        Datetime sameSecond = System.now().addHours(-1);
        seedChain(order, 'first', 'First', 1, sameSecond);
        seedChain(order, 'second', 'Second', 1, sameSecond);
        seedChain(order, 'third', 'Third', 1, sameSecond);

        AsyncJobTimelineController.TimelinePage page = loadAsOperator(order.Id, 7, 10, 0);

        Assert.areEqual(new List<String>{ 'third', 'second', 'first' }, chainIdsOf(page));
    }

    @IsTest
    private static void shouldCountChainsByStatusAcrossTheWholeRangeAndFilterByIt() {
        Account order = new Account(Name = 'Order');
        insert order;
        seedChain(order, 'done', 'Done run', 1, System.now().addHours(-1));
        List<AsyncResult__c> failed = seedChain(
            order,
            'bad',
            'Bad run',
            2,
            System.now().addHours(-2)
        );
        failed[1].Status__c = QueueableManager.STATUS_FAILED;
        update failed[1];
        List<AsyncResult__c> live = seedChain(
            order,
            'live',
            'Live run',
            2,
            System.now().addHours(-3)
        );
        live[1].Status__c = QueueableManager.STATUS_ENQUEUED;
        update live[1];

        AsyncJobTimelineController.TimelinePage firstOnly = loadAsOperator(order.Id, 7, 1, 0);
        AsyncJobTimelineController.TimelinePage onlyFailed = loadAsOperator(
            order.Id,
            7,
            10,
            0,
            'failed'
        );
        AsyncJobTimelineController.TimelinePage onlyDone = loadAsOperator(
            order.Id,
            7,
            10,
            0,
            'completed'
        );

        Assert.areEqual(1, firstOnly.sequences.size());
        Assert.areEqual(3, firstOnly.counts.get('all'), 'Counts cover the range, not the page.');
        Assert.areEqual(1, firstOnly.counts.get('inflight'));
        Assert.areEqual(1, firstOnly.counts.get('failed'));
        Assert.areEqual(1, firstOnly.counts.get('completed'));
        Assert.areEqual(new List<String>{ 'bad' }, chainIdsOf(onlyFailed));
        Assert.areEqual(1, onlyFailed.totalChainCount);
        Assert.areEqual(new List<String>{ 'done' }, chainIdsOf(onlyDone));
    }

    @IsTest
    private static void shouldCountAPageChainByTheRowsReadForThePage() {
        Account order = new Account(Name = 'Order');
        insert order;
        List<AsyncResult__c> live = seedChain(
            order,
            'live',
            'Live run',
            2,
            System.now().addHours(-1)
        );
        live[1].Status__c = QueueableManager.STATUS_ENQUEUED;
        update live[1];
        Account otherOrder = new Account(Name = 'Other order');
        insert otherOrder;
        seedChain(otherOrder, 'elsewhere', 'Elsewhere run', 1, System.now().addHours(-1));
        AsyncJobTimelineChains chains;
        System.runAs(operator()) {
            chains = new AsyncJobTimelineChains(order.Id, 7);
        }
        live[1].Status__c = QueueableManager.STATUS_COMPLETED;
        update live[1];

        chains.refreshFrom([SELECT ChainId__c, Status__c FROM AsyncResult__c]);

        Assert.areEqual(
            0,
            chains.counts().get('inflight'),
            'The step finished after the snapshot.'
        );
        Assert.areEqual(1, chains.counts().get('completed'));
        Assert.areEqual(1, chains.counts().get('all'), 'Rows of another record are ignored.');
    }

    @IsTest
    private static void shouldLinkARequeuedRowToItsReplay() {
        Account order = new Account(Name = 'Order');
        insert order;
        List<AsyncResult__c> source = seedChain(
            order,
            'source',
            'Source',
            1,
            System.now().addHours(-2)
        );
        source[0].Status__c = QueueableManager.STATUS_FAILED;
        source[0].RequeueStatus__c = 'Requeued';
        update source[0];
        List<AsyncResult__c> replay = seedChain(
            order,
            'replay',
            'Replay',
            1,
            System.now().addHours(-1)
        );
        replay[0].RequeuedFrom__c = source[0].Id;
        update replay[0];

        AsyncJobTimelineController.TimelinePage page = loadAsOperator(order.Id, 7, 10, 0);

        AsyncJobTimelineController.Sequence sourceSequence = page.sequences[1];
        Assert.areEqual('source', sourceSequence.chainId);
        Assert.areEqual(replay[0].Id, sourceSequence.steps[0].replayResultId);
        Assert.areEqual('replay', sourceSequence.steps[0].replayChainId);
    }

    @IsTest
    private static void shouldLoadAllTimeWhenDaysBackIsZero() {
        Account order = new Account(Name = 'Order');
        insert order;
        seedChain(order, 'ancient', 'Ancient run', 1, System.now().addDays(-400));
        seedChain(order, 'recent', 'Recent run', 1, System.now().addHours(-1));

        AsyncJobTimelineController.TimelinePage page = loadAsOperator(order.Id, 0, 10, 0);

        Assert.areEqual(new List<String>{ 'recent', 'ancient' }, chainIdsOf(page));
        Assert.areEqual(0, page.olderChainCount);
        Assert.areEqual(2, page.totalChainCount);
    }

    @IsTest
    private static void shouldPageByChainsAndCountOlderOnes() {
        Account order = new Account(Name = 'Order');
        insert order;
        seedChain(order, 'one', null, 1, System.now().addDays(-2));
        seedChain(order, 'two', null, 1, System.now().addDays(-3));
        seedChain(order, 'three', null, 1, System.now().addDays(-4));
        seedChain(order, 'older-a', null, 1, System.now().addDays(-9));
        seedChain(order, 'older-b', null, 1, System.now().addDays(-12));

        AsyncJobTimelineController.TimelinePage first = loadAsOperator(order.Id, 7, 2, 0);
        AsyncJobTimelineController.TimelinePage second = loadAsOperator(order.Id, 7, 2, 2);
        AsyncJobTimelineController.TimelinePage onlyOld = loadAsOperator(order.Id, 1, 10, 0);

        Assert.areEqual(new List<String>{ 'one', 'two' }, chainIdsOf(first));
        Assert.isTrue(first.hasMore);
        Assert.areEqual(new List<String>{ 'three' }, chainIdsOf(second));
        Assert.isFalse(second.hasMore);
        Assert.areEqual(2, first.olderChainCount);
        Assert.isTrue(onlyOld.sequences.isEmpty(), 'Nothing in the last day.');
        Assert.areEqual(5, onlyOld.olderChainCount, 'Everything is older than a day.');
    }

    @IsTest
    private static void shouldNameAnUnnamedSequenceAfterItsFirstJob() {
        Account order = new Account(Name = 'Order');
        insert order;
        seedChain(order, 'unnamed', null, 2, System.now());

        AsyncJobTimelineController.TimelinePage page = loadAsOperator(order.Id, 7, 10, 0);

        Assert.areEqual('Step 1', page.sequences[0].name, 'The job name of the first step.');
    }

    @IsTest
    private static void shouldJoinApexJobStatusForEnqueuedRows() {
        Account order = new Account(Name = 'Order');
        insert order;
        Id apexJobId = System.enqueueJob(new NoopQueueable());
        AsyncResult__c waiting = seedChain(order, 'live', null, 1, System.now())[0];
        waiting.Status__c = QueueableManager.STATUS_ENQUEUED;
        waiting.SalesforceJobId__c = apexJobId;
        update waiting;

        AsyncJobTimelineController.TimelinePage page = loadAsOperator(order.Id, 7, 10, 0);
        AsyncJobTimelineController.PollResult polled = pollAsOperator(order.Id, 'live');

        Assert.areEqual('Queued', page.sequences[0].steps[0].apexJobStatus);
        Assert.areEqual('Queued', polled.apexJobStatusById.get(apexJobId));
    }

    @IsTest
    private static void shouldShowAnExternalLinkWithItsKeyAsTheName() {
        Account order = new Account(Name = 'Order');
        insert order;
        AsyncResult__c step = seedChain(order, 'ext', null, 1, System.now())[0];
        insert new AsyncResultLink__c(
            AsyncResult__c = step.Id,
            Key__c = '4711',
            Source__c = 'NetSuite',
            ObjectName__c = 'Customer'
        );

        AsyncJobTimelineController.TimelinePage page = loadAsOperator(order.Id, 7, 10, 0);

        AsyncJobTimelineController.LinkedRecord external = page.sequences[0].steps[0].records[1];
        Assert.areEqual('4711', external.key);
        Assert.areEqual('NetSuite', external.source);
        Assert.areEqual('Customer', external.objectName);
        Assert.areEqual('4711', external.name, 'No Salesforce name to look up.');
    }

    @IsTest
    private static void shouldResolveLinkedRecordNamesPerObjectType() {
        Account order = new Account(Name = 'Order');
        insert order;
        Id taskId = Id.valueOf(Task.SObjectType.getDescribe().getKeyPrefix() + '000000000001');
        AsyncResult__c step = seedChain(order, 'links', null, 1, System.now())[0];
        insert new AsyncResultLink__c(
            AsyncResult__c = step.Id,
            Key__c = taskId,
            Source__c = QueueableManager.SOURCE_SALESFORCE,
            ObjectName__c = 'Task'
        );

        AsyncJobTimelineController.TimelinePage page = loadAsOperator(order.Id, 7, 10, 0);

        Map<String, String> nameById = new Map<String, String>();
        for (AsyncJobTimelineController.LinkedRecord linked : page.sequences[0].steps[0].records) {
            nameById.put(linked.key, linked.name);
        }
        Assert.areEqual('Order', nameById.get(order.Id));
        Assert.areEqual(
            String.valueOf(taskId),
            nameById.get(taskId),
            'A record without a readable name shows its id.'
        );
    }

    @IsTest
    private static void shouldKeepTheFingerprintWhenNothingMoved() {
        Account order = new Account(Name = 'Order');
        insert order;
        seedChain(order, 'stable', null, 2, System.now());

        AsyncJobTimelineController.TimelinePage page = loadAsOperator(order.Id, 7, 10, 0);
        AsyncJobTimelineController.PollResult polled = pollAsOperator(order.Id, 'stable');

        Assert.areEqual(page.fingerprint, polled.fingerprint);
    }

    @IsTest
    private static void shouldChangeTheFingerprintWhenARowIsUpdated() {
        Account order = new Account(Name = 'Order');
        insert order;
        AsyncResult__c step = seedChain(order, 'moving', null, 1, System.now().addMinutes(-5))[0];
        AsyncJobTimelineController.TimelinePage page = loadAsOperator(order.Id, 7, 10, 0);

        step.Status__c = QueueableManager.STATUS_FAILED;
        update step;
        AsyncJobTimelineController.PollResult polled = pollAsOperator(order.Id, 'moving');

        Assert.areNotEqual(page.fingerprint, polled.fingerprint);
    }

    @IsTest
    private static void shouldChangeTheFingerprintWhenANewChainIsLinked() {
        Account order = new Account(Name = 'Order');
        insert order;
        seedChain(order, 'first', null, 1, System.now());
        AsyncJobTimelineController.TimelinePage page = loadAsOperator(order.Id, 7, 10, 0);

        seedChain(order, 'second', null, 1, System.now());
        AsyncJobTimelineController.PollResult polled = pollAsOperator(order.Id, 'first');

        Assert.areNotEqual(page.fingerprint, polled.fingerprint);
    }

    @IsTest
    private static void shouldRejectRequeueWithoutTheCustomPermission() {
        User viewer = userWith('tlvw', new List<String>{ RESULT_ACCESS });
        Account order = new Account(Name = 'Order');
        insert order;
        AsyncResult__c step = seedChain(order, 'failed', null, 1, System.now())[0];
        String message;

        System.runAs(viewer) {
            try {
                AsyncJobTimelineController.requeue(new List<Id>{ step.Id });
            } catch (AuraHandledException ex) {
                message = ex.getMessage();
            }
        }

        Assert.areEqual(QueueableManager.ERROR_MESSAGE_REQUEUE_PERMISSION, message);
    }

    @IsTest
    private static void shouldRequeueWithTheCustomPermission() {
        User operator = operator();
        Account order = new Account(Name = 'Order');
        insert order;
        AsyncResult__c step = seedChain(order, 'failed', null, 1, System.now())[0];
        TimelineRequeueJob job = new TimelineRequeueJob();
        job.tag = 'REPLAYED';
        step.ClassName__c = job.className;
        step.JobPayload__c = JobPayload.forJob(job);
        step.PayloadSize__c = step.JobPayload__c.length();
        step.RequeueStatus__c = AsyncRequeue.STATUS_STORED;
        update step;

        AsyncJobTimelineController.RequeueOutcome outcome;
        System.runAs(operator) {
            Test.startTest();
            outcome = AsyncJobTimelineController.requeue(new List<Id>{ step.Id });
            Test.stopTest();
        }

        Assert.areEqual(new List<Id>{ step.Id }, outcome.requeued);
        Assert.isNotNull(outcome.chainId, 'The new chain, so the UI can scroll to it.');
        Assert.areEqual(1, [SELECT COUNT() FROM Account WHERE Name = 'REPLAYED']);
    }

    @IsTest
    private static void shouldExplainMissingAccessToResults() {
        User outsider = userWith('tlout', new List<String>());
        Account order = new Account(Name = 'Order');
        insert order;
        seedChain(order, 'hidden', null, 1, System.now());
        String message;

        System.runAs(outsider) {
            try {
                AsyncJobTimelineController.load(request(order.Id, 7, 10, 0, null));
            } catch (AuraHandledException ex) {
                message = ex.getMessage();
            }
        }

        Assert.areEqual(AsyncJobTimelineController.ERROR_MESSAGE_NO_ACCESS, message);
    }

    private static List<AsyncResult__c> seedChain(
        Account linked,
        String chainId,
        String chainName,
        Integer steps,
        Datetime createdAt
    ) {
        List<AsyncResult__c> rows = new List<AsyncResult__c>();
        for (Integer i = 1; i <= steps; i++) {
            rows.add(
                new AsyncResult__c(
                    ChainId__c = chainId,
                    ChainName__c = chainName,
                    ChainSequence__c = i,
                    CustomJobId__c = chainId + '-' + i,
                    JobName__c = 'Step ' + i,
                    ClassName__c = 'SeedJob',
                    Status__c = QueueableManager.STATUS_COMPLETED
                )
            );
        }
        insert rows;
        List<AsyncResultLink__c> links = new List<AsyncResultLink__c>();
        for (AsyncResult__c row : rows) {
            Test.setCreatedDate(row.Id, createdAt);
            links.add(
                new AsyncResultLink__c(
                    AsyncResult__c = row.Id,
                    Key__c = linked.Id,
                    Source__c = QueueableManager.SOURCE_SALESFORCE,
                    ObjectName__c = 'Account'
                )
            );
        }
        insert links;
        return rows;
    }

    private static List<String> chainIdsOf(AsyncJobTimelineController.TimelinePage page) {
        List<String> chainIds = new List<String>();
        for (AsyncJobTimelineController.Sequence sequence : page.sequences) {
            chainIds.add(sequence.chainId);
        }
        return chainIds;
    }

    private static AsyncJobTimelineController.TimelinePage loadInFlightKeeping(
        Id recordId,
        List<String> keepChainIds
    ) {
        AsyncJobTimelineRequest request = new AsyncJobTimelineRequest();
        request.recordId = recordId;
        request.daysBack = 7;
        request.chainLimit = 10;
        request.chainOffset = 0;
        request.statusFilter = 'inflight';
        request.keepChainIds = keepChainIds;
        AsyncJobTimelineController.TimelinePage page;
        System.runAs(operator()) {
            page = AsyncJobTimelineController.load(request);
        }
        return page;
    }

    @IsTest
    static void viewerPermissionSetOpensTheCardController() {
        Id viewerPermissionSetId = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = 'AsyncResultAccess'
            LIMIT 1
        ]
        .Id;
        Id controllerClassId = [
            SELECT Id
            FROM ApexClass
            WHERE Name = 'AsyncJobTimelineController'
            LIMIT 1
        ]
        .Id;

        List<SetupEntityAccess> classAccess = [
            SELECT Id
            FROM SetupEntityAccess
            WHERE ParentId = :viewerPermissionSetId AND SetupEntityId = :controllerClassId
        ];

        Assert.areEqual(
            1,
            classAccess.size(),
            'A viewer without class access cannot call load at all'
        );
    }

    @IsTest
    private static void shouldTellAViewerWithoutAccessWhenPolling() {
        User outsider = userWith('tlpol', new List<String>());
        Account order = new Account(Name = 'Order');
        insert order;
        String message;

        System.runAs(outsider) {
            try {
                AsyncJobTimelineController.poll(order.Id, new List<String>{ 'chain' });
            } catch (AuraHandledException ex) {
                message = ex.getMessage();
            }
        }

        Assert.areEqual(AsyncJobTimelineController.ERROR_MESSAGE_NO_ACCESS, message);
    }

    @IsTest
    private static void shouldReportARequeueThatThrowsWithItsOwnMessage() {
        String message;

        System.runAs(operator()) {
            try {
                AsyncJobTimelineController.requeue(null);
            } catch (AuraHandledException ex) {
                message = ex.getMessage();
            }
        }

        Assert.isNotNull(message);
        Assert.areNotEqual('Script-thrown exception', message);
    }

    @IsTest
    private static void shouldNameTheRecordsItCanAndSkipAPrefixWithNoType() {
        Account order = new Account(Name = 'Order');
        insert order;
        Id noApexType = idOfPrefix(CaseComment.SObjectType.getDescribe().getKeyPrefix());

        Map<Id, String> nameById = AsyncJobTimelineNames.of(new Set<Id>{ order.Id, noApexType });

        Assert.areEqual(new Map<Id, String>{ order.Id => 'Order' }, nameById);
    }

    @IsTest
    private static void shouldSkipATypeWithNoNameField() {
        Account order = new Account(Name = 'Order');
        insert order;
        Id noNameField = idOfPrefix(AccountShare.SObjectType.getDescribe().getKeyPrefix());

        Map<Id, String> nameById = AsyncJobTimelineNames.of(new Set<Id>{ order.Id, noNameField });

        Assert.areEqual(new Map<Id, String>{ order.Id => 'Order' }, nameById);
    }

    @IsTest
    private static void shouldLookUpNamesForAtMostTenTypes() {
        Set<Id> oneIdPerType = new Set<Id>();
        for (
            Schema.SObjectType type : new List<Schema.SObjectType>{
                Account.SObjectType,
                Contact.SObjectType,
                Lead.SObjectType,
                Opportunity.SObjectType,
                Case.SObjectType,
                User.SObjectType,
                Campaign.SObjectType,
                Product2.SObjectType,
                Pricebook2.SObjectType,
                Contract.SObjectType,
                Order.SObjectType
            }
        ) {
            oneIdPerType.add(idOfPrefix(type.getDescribe().getKeyPrefix()));
        }

        Integer queriesBefore = Limits.getQueries();
        AsyncJobTimelineNames.of(oneIdPerType);

        Assert.areEqual(10, Limits.getQueries() - queriesBefore);
    }

    @IsTest
    private static void shouldReturnNoNameForATypeTheViewerCannotRead() {
        User outsider = userWith('tlnam', new List<String>());
        AsyncResult__c row = new AsyncResult__c(Status__c = QueueableManager.STATUS_COMPLETED);
        insert row;
        Set<Id> ids = new Set<Id>{ row.Id };
        Map<Id, String> seenByOutsider;

        System.runAs(outsider) {
            seenByOutsider = AsyncJobTimelineNames.of(ids);
        }

        Assert.isTrue(AsyncJobTimelineNames.of(ids).containsKey(row.Id));
        Assert.isTrue(seenByOutsider.isEmpty());
    }

    private static Id idOfPrefix(String keyPrefix) {
        return Id.valueOf(keyPrefix + '1'.leftPad(12, '0'));
    }

    private static User operator() {
        return [SELECT Id FROM User WHERE Alias = :OPERATOR_ALIAS LIMIT 1];
    }

    private static AsyncJobTimelineController.TimelinePage loadAsOperator(
        Id recordId,
        Integer daysBack,
        Integer chainLimit,
        Integer chainOffset
    ) {
        return loadAsOperator(recordId, daysBack, chainLimit, chainOffset, null);
    }

    private static AsyncJobTimelineController.TimelinePage loadAsOperator(
        Id recordId,
        Integer daysBack,
        Integer chainLimit,
        Integer chainOffset,
        String statusFilter
    ) {
        AsyncJobTimelineController.TimelinePage page;
        System.runAs(operator()) {
            page = AsyncJobTimelineController.load(
                request(recordId, daysBack, chainLimit, chainOffset, statusFilter)
            );
        }
        return page;
    }

    private static AsyncJobTimelineRequest request(
        Id recordId,
        Integer daysBack,
        Integer chainLimit,
        Integer chainOffset,
        String statusFilter
    ) {
        AsyncJobTimelineRequest request = new AsyncJobTimelineRequest();
        request.recordId = recordId;
        request.daysBack = daysBack;
        request.chainLimit = chainLimit;
        request.chainOffset = chainOffset;
        request.statusFilter = statusFilter;
        return request;
    }

    private static AsyncJobTimelineController.PollResult pollAsOperator(
        Id recordId,
        String chainId
    ) {
        AsyncJobTimelineController.PollResult polled;
        System.runAs(operator()) {
            polled = AsyncJobTimelineController.poll(recordId, new List<String>{ chainId });
        }
        return polled;
    }

    private static User userWith(String alias, List<String> permissionSetNames) {
        Profile standard = [SELECT Id FROM Profile WHERE Name = 'Standard User'];
        User created = new User(
            Alias = alias,
            Email = 'timeline@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Timeline',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = standard.Id,
            TimeZoneSidKey = 'GMT',
            Username = alias + '.' + System.now().getTime() + '@example.com'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert created;
            List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
            for (PermissionSet permissionSet : [
                SELECT Id
                FROM PermissionSet
                WHERE Name IN :permissionSetNames
            ]) {
                assignments.add(
                    new PermissionSetAssignment(
                        AssigneeId = created.Id,
                        PermissionSetId = permissionSet.Id
                    )
                );
            }
            insert assignments;
        }
        return created;
    }

    public class NoopQueueable implements Queueable {
        public void execute(QueueableContext ctx) {
        }
    }

    public class TimelineRequeueJob extends QueueableJob {
        public String tag;

        public override void work() {
            insert new Account(Name = tag);
        }
    }
}
