let counter = 0;

export const step = overrides => {
    counter += 1;
    return {
        id: 'a0' + String(counter).padStart(13, '0'),
        name: 'AR-' + String(counter).padStart(5, '0'),
        customJobId: 'job-' + counter,
        className: 'StepJob',
        jobName: 'Step ' + counter,
        status: 'COMPLETED',
        createdAt: '2026-11-02T09:00:00.000Z',
        startedAt: '2026-11-02T09:00:01.000Z',
        finishedAt: '2026-11-02T09:00:03.000Z',
        records: [],
        ...overrides
    };
};

export const sequence = (chainId, steps, overrides = {}) => ({
    chainId,
    name: 'Order fulfilment pipeline',
    startedAt: '2026-11-02T09:00:00.000Z',
    steps,
    ...overrides
});

export const page = (sequences, overrides = {}) => ({
    sequences,
    hasMore: false,
    olderChainCount: 0,
    canRequeue: true,
    fingerprint: 'fp-1',
    loadedAt: '2026-11-02T09:05:00.000Z',
    ...overrides
});

export const failedSequence = () =>
    sequence('chain-failed', [
        step({ chainSequence: 1, customJobId: 'f1', jobName: 'Reserve stock' }),
        step({ chainSequence: 2, customJobId: 'f2', jobName: 'Create invoice', priority: 1 }),
        step({
            chainSequence: 3,
            customJobId: 'f3',
            jobName: 'Commission split',
            status: 'FAILED',
            exceptionType: 'System.DmlException',
            exceptionMessage: 'UNABLE_TO_LOCK_ROW: record is being modified',
            retryAttempts: 2,
            retryHistory: 'Attempt 1: ...\nAttempt 2: ...',
            requeueStatus: 'Stored'
        }),
        step({
            chainSequence: 4,
            customJobId: 'f4',
            jobName: 'Account rollups',
            status: 'SKIPPED_DEPENDENCY',
            skipReason: "Dependency 'CommissionSplitJob' required SUCCESS but was FAILURE",
            requeueStatus: 'Stored',
            dependencies: JSON.stringify([
                { resolvedTargetCustomJobId: 'f3', requiredOutcome: 'SUCCESS' }
            ])
        }),
        step({
            chainSequence: 5,
            customJobId: 'f5',
            jobName: 'Sync to ERP',
            status: 'SKIPPED_DEPENDENCY',
            requeueStatus: null
        })
    ]);

export const runningSequence = () =>
    sequence(
        'chain-running',
        [
            step({
                chainSequence: 1,
                customJobId: 'r1',
                jobName: 'Commission split',
                records: [
                    {
                        key: '001000000000001AAA',
                        name: 'Order #10248',
                        objectName: 'Account',
                        source: 'Salesforce'
                    }
                ]
            }),
            step({
                chainSequence: 2,
                customJobId: 'r2',
                jobName: 'Account rollups',
                status: 'ENQUEUED',
                apexJobStatus: 'Processing',
                salesforceJobId: '707000000000001AAA',
                finishedAt: null
            }),
            step({
                chainSequence: 3,
                customJobId: 'r3',
                jobName: 'Notify sales',
                status: 'ENQUEUED',
                finishedAt: null
            })
        ],
        { name: 'Order fulfilment pipeline' }
    );

export const completedSequence = (chainId = 'chain-done') =>
    sequence(
        chainId,
        [step({ chainSequence: 1 }), step({ chainSequence: 2 }), step({ chainSequence: 3 })],
        { name: 'Nightly price refresh' }
    );

export const longSequence = (count, failedAt) =>
    sequence(
        'chain-long',
        Array.from({ length: count }, (_, i) =>
            step({
                chainSequence: i + 1,
                customJobId: 'l' + (i + 1),
                status: i + 1 === failedAt ? 'FAILED' : 'COMPLETED',
                requeueStatus: 'Stored'
            })
        ),
        { name: 'Long run' }
    );

export const flushPromises = async () => {
    for (let turn = 0; turn < 10; turn++) {
        // eslint-disable-next-line no-await-in-loop
        await Promise.resolve();
    }
};
