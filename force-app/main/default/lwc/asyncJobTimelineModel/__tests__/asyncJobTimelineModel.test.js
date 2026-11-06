import {
    CAPS,
    currentRowKey,
    POLL,
    statusOf,
    groupSteps,
    sequenceSummary,
    collapseCompletedRuns,
    diffRows,
    formatDuration,
    relativeTime,
    tagsFor,
    failedPageGroups,
    rowKeyOf,
    pluralOf,
    nextPollDelay,
    pollDelayFor,
    recordsOf,
    RANGES,
    pageStripFor,
    delayOf,
    truncate,
    sameData
} from 'c/asyncJobTimelineModel';

const step = overrides => ({
    id: 'a0' + Math.random().toString(16).slice(2, 10),
    customJobId: overrides.customJobId || 'job-' + overrides.chainSequence,
    jobName: 'Step ' + overrides.chainSequence,
    className: 'StepJob',
    status: 'COMPLETED',
    records: [],
    ...overrides
});

describe('statusOf', () => {
    it('maps outcomes to glyph keys and labels', () => {
        expect(statusOf(step({ chainSequence: 1 }))).toEqual({ key: 'ok', label: 'Completed' });
        expect(statusOf(step({ chainSequence: 1, status: 'FAILED' }))).toEqual({
            key: 'bad',
            label: 'Failed'
        });
        expect(statusOf(step({ chainSequence: 1, status: 'SKIPPED_DEPENDENCY' }))).toEqual({
            key: 'skip',
            label: 'Skipped · dependency'
        });
        expect(statusOf(step({ chainSequence: 1, status: 'SKIPPED_CHAIN_STOPPED' })).label).toBe(
            'Skipped · chain stopped'
        );
        expect(statusOf(step({ chainSequence: 1, status: 'FRAMEWORK_ERROR' })).key).toBe('bad');
    });

    it('derives running, queued, retrying and aborted from the platform job', () => {
        expect(
            statusOf(step({ chainSequence: 1, status: 'ENQUEUED', apexJobStatus: 'Processing' }))
        ).toEqual({
            key: 'run',
            label: 'Running'
        });
        expect(
            statusOf(step({ chainSequence: 1, status: 'ENQUEUED', apexJobStatus: 'Queued' })).label
        ).toBe('Queued');
        expect(statusOf(step({ chainSequence: 1, status: 'ENQUEUED' })).label).toBe('Enqueued');
        expect(
            statusOf(step({ chainSequence: 1, status: 'ENQUEUED', apexJobStatus: 'Completed' }))
        ).toEqual({ key: 'run', label: 'Finishing' });
        expect(
            statusOf(step({ chainSequence: 1, status: 'ENQUEUED', apexJobStatus: 'Aborted' })).key
        ).toBe('bad');
        expect(
            statusOf(
                step({
                    chainSequence: 1,
                    status: 'ENQUEUED',
                    retryAttempts: 1,
                    nextAttemptAt: '2026-11-02T10:00:00Z'
                })
            )
        ).toEqual({ key: 'retry', label: 'Retrying' });
    });
});

describe('currentRowKey', () => {
    const rows = statuses =>
        groupSteps(
            statuses.map((status, i) =>
                step({
                    chainSequence: i + 1,
                    customJobId: 'j' + (i + 1),
                    status: status === 'COMPLETED' ? 'COMPLETED' : 'ENQUEUED',
                    apexJobStatus: status === 'COMPLETED' ? null : status,
                    finishedAt: status === 'COMPLETED' ? '2026-11-02T10:00:01Z' : null
                })
            )
        );

    it('points at the running step, else the one the platform holds in its queue', () => {
        expect(currentRowKey(rows(['COMPLETED', 'Processing', 'Queued', null]))).toBe('j2');
        expect(currentRowKey(rows(['COMPLETED', 'Completed', null]))).toBe('j2');
        expect(currentRowKey(rows(['COMPLETED', 'Queued', null]))).toBe('j2');
        expect(currentRowKey(rows(['COMPLETED', null, null]))).toBeNull();
        expect(currentRowKey(rows(['COMPLETED', 'COMPLETED']))).toBeNull();
    });

    it('counts a scheduled retry as held by the platform', () => {
        const retrying = groupSteps([
            step({
                chainSequence: 1,
                customJobId: 'j1',
                status: 'ENQUEUED',
                retryAttempts: 1,
                nextAttemptAt: '2026-11-02T10:00:00Z',
                finishedAt: null
            }),
            step({ chainSequence: 2, customJobId: 'j2', status: 'ENQUEUED', finishedAt: null })
        ]);
        expect(currentRowKey(retrying)).toBe('j1');
    });
});

describe('groupSteps', () => {
    const steps = [
        step({ chainSequence: 3, customJobId: 'c3' }),
        step({ chainSequence: 1, customJobId: 'c1' }),
        step({ chainSequence: 1, customJobId: 'fin', parentCustomJobId: 'c1', jobName: 'Audit' }),
        step({
            chainSequence: 2,
            customJobId: 'p1',
            chunkRunId: 'p1',
            chunkPage: 1,
            chunkPages: 3
        }),
        step({
            chainSequence: 2,
            customJobId: 'p2',
            chunkRunId: 'p1',
            chunkPage: 2,
            chunkPages: 3,
            status: 'FAILED'
        }),
        step({
            chainSequence: 2,
            customJobId: 'p3',
            chunkRunId: 'p1',
            chunkPage: 3,
            chunkPages: 3,
            status: 'ENQUEUED'
        })
    ];

    it('orders by chain sequence, nests finalizers and folds chunk pages into one row', () => {
        const rows = groupSteps(steps);
        expect(rows.map(row => row.step.customJobId)).toEqual(['c1', 'fin', 'p1', 'c3']);
        expect(rows.map(row => row.kind)).toEqual(['job', 'finalizer', 'chunk', 'job']);
        expect(rows[1].depth).toBe(1);
        expect(rows[2].pages).toHaveLength(3);
        expect(rows[2].status).toEqual({ key: 'wait', label: 'Enqueued' });
    });

    it('reports a chunk run with failed pages as failed once every page settled', () => {
        const settled = steps.map(s => {
            return s.customJobId === 'p3' ? { ...s, status: 'COMPLETED' } : s;
        });
        const rows = groupSteps(settled);
        expect(rows[2].status).toEqual({ key: 'bad', label: '1 page failed' });
    });
});

describe('sequenceSummary', () => {
    it('counts rows, computes percent, status precedence and duration', () => {
        const rows = groupSteps([
            step({
                chainSequence: 1,
                startedAt: '2026-11-02T10:00:00.000Z',
                finishedAt: '2026-11-02T10:00:02.000Z'
            }),
            step({
                chainSequence: 2,
                status: 'FAILED',
                startedAt: '2026-11-02T10:00:03.000Z',
                finishedAt: '2026-11-02T10:00:04.500Z'
            }),
            step({ chainSequence: 3, status: 'SKIPPED_DEPENDENCY' }),
            step({ chainSequence: 4, status: 'ENQUEUED', apexJobStatus: 'Queued' })
        ]);
        const summary = sequenceSummary(rows);
        expect(summary).toMatchObject({
            total: 4,
            completed: 1,
            failed: 1,
            skipped: 1,
            waiting: 1,
            running: 0,
            percent: 25
        });
        expect(summary.status).toBe('running');
        expect(summary.durationMs).toBe(4500);
    });

    it('prefers running over queued, and failed over completed when nothing is in flight', () => {
        const running = sequenceSummary(
            groupSteps([
                step({ chainSequence: 1, status: 'ENQUEUED', apexJobStatus: 'Processing' }),
                step({ chainSequence: 2, status: 'ENQUEUED' })
            ])
        );
        expect(running.status).toBe('running');
        const failed = sequenceSummary(
            groupSteps([step({ chainSequence: 1 }), step({ chainSequence: 2, status: 'FAILED' })])
        );
        expect(failed.status).toBe('failed');
        const done = sequenceSummary(groupSteps([step({ chainSequence: 1 })]));
        expect(done.status).toBe('completed');
        expect(done.percent).toBe(100);
    });
});

describe('collapseCompletedRuns', () => {
    const manySteps = (count, failedAt) =>
        groupSteps(
            Array.from({ length: count }, (_, i) =>
                step({ chainSequence: i + 1, status: i + 1 === failedAt ? 'FAILED' : 'COMPLETED' })
            )
        );

    it('leaves short sequences alone', () => {
        expect(collapseCompletedRuns(manySteps(CAPS.stepsCollapsed))).toHaveLength(
            CAPS.stepsCollapsed
        );
    });

    it('keeps the first 3, the last 2 and every non-completed row, folding the rest into gaps', () => {
        const rows = collapseCompletedRuns(manySteps(30, 17));
        const kinds = rows.map(row => {
            return row.kind === 'gap' ? 'gap:' + row.hiddenCount : row.step.chainSequence;
        });
        expect(kinds).toEqual([1, 2, 3, 'gap:13', 17, 'gap:11', 29, 30]);
    });

    it('expands a gap back into its rows', () => {
        const rows = collapseCompletedRuns(manySteps(30, 17));
        expect(rows[3].hiddenRows).toHaveLength(13);
        expect(rows[3].hiddenRows[0].step.chainSequence).toBe(4);
    });
});

describe('diffRows', () => {
    it('finds added and changed rows by custom job id', () => {
        const before = groupSteps([
            step({ chainSequence: 1, customJobId: 'a' }),
            step({ chainSequence: 2, customJobId: 'b', status: 'ENQUEUED' })
        ]);
        const after = groupSteps([
            step({ chainSequence: 1, customJobId: 'a' }),
            step({ chainSequence: 2, customJobId: 'x', addedByCustomJobId: 'a' }),
            step({
                chainSequence: 3,
                customJobId: 'b',
                status: 'ENQUEUED',
                apexJobStatus: 'Processing'
            })
        ]);
        const diff = diffRows(before, after);
        expect([...diff.added]).toEqual(['x']);
        expect([...diff.changed]).toEqual(['b']);
    });

    it('treats the first load as nothing new', () => {
        const diff = diffRows(null, groupSteps([step({ chainSequence: 1 })]));
        expect(diff.added.size).toBe(0);
    });
});

describe('formatDuration', () => {
    it('keeps one decimal under a second and whole seconds above', () => {
        expect(formatDuration(900)).toBe('0.9 s');
        expect(formatDuration(40)).toBe('<0.1 s');
        expect(formatDuration(1800)).toBe('2 s');
        expect(formatDuration(24400)).toBe('24 s');
        expect(formatDuration(72000)).toBe('1 min 12 s');
        expect(formatDuration(3720000)).toBe('1 h 2 min');
        expect(formatDuration(null)).toBeNull();
        expect(formatDuration(-5)).toBeNull();
    });
});

describe('relativeTime', () => {
    const now = Date.parse('2026-11-03T14:00:00.000Z');
    const at = iso => relativeTime(iso, now);

    it('counts minutes and hours back, then falls back to the date', () => {
        expect(at('2026-11-03T13:59:40.000Z').text).toBe('just now');
        expect(at('2026-11-03T13:40:00.000Z').text).toBe('20 min ago');
        expect(at('2026-11-03T12:30:00.000Z').text).toBe('1 h 30 min ago');
        expect(at('2026-11-02T13:54:00.000Z').text).toMatch(/^Yesterday, /);
        expect(at('2026-10-31T13:54:00.000Z').text).toMatch(/^[A-Z][a-z]{2}, /);
        expect(at('2026-10-20T13:54:00.000Z').text).toMatch(/2026/);
        expect(at('2026-10-20T13:54:00.000Z').full).toMatch(/2026/);
        expect(relativeTime(null, now)).toBeNull();
    });
});

describe('RANGES', () => {
    it('offers a day, a week, a month and all time, with 0 meaning all', () => {
        expect(RANGES.map(range => range.days)).toEqual([1, 7, 30, 0]);
        expect(RANGES.find(range => range.days === 0).label).toBe('All time');
    });
});

describe('recordsOf', () => {
    it('unions the linked records of every chunk page without duplicates', () => {
        const order = {
            key: '001000000000001AAA',
            name: 'Order',
            objectName: 'Account',
            source: 'Salesforce'
        };
        const rows = groupSteps([
            step({
                chainSequence: 1,
                customJobId: 'p1',
                chunkRunId: 'run',
                chunkPage: 1,
                chunkPages: 2,
                records: [
                    order,
                    {
                        key: '001000000000002AAA',
                        name: 'Line 0',
                        objectName: 'Account',
                        source: 'Salesforce'
                    }
                ]
            }),
            step({
                chainSequence: 1,
                customJobId: 'p2',
                chunkRunId: 'run',
                chunkPage: 2,
                chunkPages: 2,
                records: [
                    order,
                    {
                        key: '001000000000003AAA',
                        name: 'Line 1',
                        objectName: 'Account',
                        source: 'Salesforce'
                    }
                ]
            })
        ]);
        expect(recordsOf(rows[0]).map(record => record.name)).toEqual([
            'Order',
            'Line 0',
            'Line 1'
        ]);
    });
});

describe('tagsFor', () => {
    const names = { c1: 'Create invoice' };

    const labelsOf = tags => tags.map(tag => tag.label);

    it('lists every tag, most specific first, each naming the job it points at', () => {
        const row = groupSteps([
            step({
                chainSequence: 2,
                customJobId: 'x',
                addedByCustomJobId: 'c1',
                priority: 1,
                dependencies: JSON.stringify([
                    { resolvedTargetCustomJobId: 'c2', requiredOutcome: 'SUCCESS' }
                ])
            })
        ])[0];
        expect(tagsFor(row, { ...names, c2: 'Reserve stock' })).toEqual([
            { label: '↳ added by Create invoice', targetJobId: 'c1' },
            { label: 'after Reserve stock succeeded', targetJobId: 'c2' },
            { label: 'P1', targetJobId: undefined }
        ]);
    });

    it('describes finalizers, chunk pages and non-requeueable failures', () => {
        const rows = groupSteps([
            step({ chainSequence: 1, customJobId: 'c1' }),
            step({ chainSequence: 1, customJobId: 'f', parentCustomJobId: 'c1' }),
            step({
                chainSequence: 2,
                customJobId: 'p1',
                chunkRunId: 'p1',
                chunkPage: 1,
                chunkPages: 12,
                status: 'ENQUEUED'
            }),
            step({
                chainSequence: 3,
                customJobId: 'bad',
                status: 'FAILED',
                requeueStatus: 'TooLarge'
            })
        ]);
        expect(labelsOf(tagsFor(rows[1], names))).toEqual(['finalizer of Create invoice']);
        expect(labelsOf(tagsFor(rows[2], names))).toEqual(['chunk · 12 pages']);
        const settled = groupSteps([
            step({
                chainSequence: 2,
                customJobId: 'q1',
                chunkRunId: 'q1',
                chunkPage: 1,
                chunkPages: 2
            }),
            step({
                chainSequence: 2,
                customJobId: 'q2',
                chunkRunId: 'q1',
                chunkPage: 2,
                chunkPages: 2
            })
        ]);
        expect(labelsOf(tagsFor(settled[0], names))).toEqual(['chunk · 2 pages']);
        expect(pageStripFor(settled[0]).summary).toBe('2 of 2 pages');
        expect(labelsOf(tagsFor(rows[3], names))).toEqual(['not requeueable']);
        const replayed = groupSteps([
            step({
                chainSequence: 3,
                customJobId: 'done',
                status: 'FAILED',
                requeueStatus: 'Requeued'
            })
        ]);
        expect(labelsOf(tagsFor(replayed[0], names))).toEqual(['requeued']);
        expect(labelsOf(tagsFor(rows[0], names))).toEqual([]);
    });
});

describe('nextPollDelay', () => {
    it('polls fast while running, slow while queued, not at all when settled', () => {
        expect(nextPollDelay({ status: 'running' })).toBe(POLL.running);
        expect(nextPollDelay({ status: 'queued' })).toBe(POLL.queued);
        expect(nextPollDelay({ status: 'failed' })).toBeNull();
        expect(nextPollDelay({ status: 'completed' })).toBeNull();
    });
});

describe('pollDelayFor', () => {
    const now = Date.parse('2026-11-03T14:00:00.000Z');
    const rowsWith = (...overrides) =>
        groupSteps(
            overrides.map((o, i) => step({ chainSequence: i + 1, customJobId: 'q' + i, ...o }))
        );

    it('polls fast while something runs or is finishing on the platform', () => {
        expect(
            pollDelayFor(rowsWith({ status: 'ENQUEUED', apexJobStatus: 'Processing' }), now)
        ).toBe(POLL.running);
        expect(
            pollDelayFor(rowsWith({ status: 'ENQUEUED', apexJobStatus: 'Completed' }), now)
        ).toBe(POLL.running);
    });

    it('polls at the queued rate while a job waits in the flex queue', () => {
        expect(pollDelayFor(rowsWith({ status: 'ENQUEUED', apexJobStatus: 'Queued' }), now)).toBe(
            POLL.queued
        );
        expect(pollDelayFor(rowsWith({ status: 'ENQUEUED' }), now)).toBe(POLL.queued);
    });

    it('sleeps until the earliest retry when every in-flight step is a scheduled retry', () => {
        const rows = rowsWith(
            { status: 'ENQUEUED', retryAttempts: 1, nextAttemptAt: '2026-11-03T14:02:00.000Z' },
            { status: 'ENQUEUED', retryAttempts: 1, nextAttemptAt: '2026-11-03T14:30:00.000Z' }
        );
        expect(pollDelayFor(rows, now)).toBe(120000);
        const soon = rowsWith({
            status: 'ENQUEUED',
            retryAttempts: 1,
            nextAttemptAt: '2026-11-03T14:00:02.000Z'
        });
        expect(pollDelayFor(soon, now)).toBe(POLL.queued);
        const far = rowsWith({
            status: 'ENQUEUED',
            retryAttempts: 1,
            nextAttemptAt: '2026-11-03T15:00:00.000Z'
        });
        expect(pollDelayFor(far, now)).toBe(POLL.maxSleep);
    });

    it('returns null when nothing is in flight', () => {
        expect(pollDelayFor(rowsWith({ status: 'COMPLETED' }), now)).toBeNull();
    });
});

describe('a delayed job', () => {
    const inMinutes = minutes => new Date(Date.now() + minutes * 60000).toISOString();
    const delayed = (overrides = {}) =>
        step({
            status: 'ENQUEUED',
            apexJobStatus: 'Queued',
            delayMinutes: 5,
            nextAttemptAt: inMinutes(5),
            ...overrides
        });

    it('is delayed until its time, then plainly queued', () => {
        expect(statusOf(delayed())).toEqual({ key: 'delay', label: 'Delayed' });
        expect(statusOf(delayed({ nextAttemptAt: inMinutes(-1) }))).toEqual({
            key: 'wait',
            label: 'Queued'
        });
    });

    it('stays enqueued with no time while it is not its turn', () => {
        const waiting = delayed({ apexJobStatus: null, nextAttemptAt: null, delayMinutes: 10 });
        const row = groupSteps([waiting])[0];
        expect(row.status).toEqual({ key: 'wait', label: 'Enqueued' });
        expect(delayOf(row)).toEqual({ until: null, plannedMinutes: 10 });
    });

    it('gives the time on the row once it is waiting, and drops the planned delay', () => {
        const next = inMinutes(5);
        expect(delayOf(groupSteps([delayed({ nextAttemptAt: next })])[0])).toEqual({
            until: next,
            plannedMinutes: null
        });
    });

    it('says nothing about a delay on a job that has none', () => {
        expect(delayOf(groupSteps([step({ status: 'ENQUEUED' })])[0])).toEqual({
            until: null,
            plannedMinutes: null
        });
    });

    it('does not mistake a retry wait for a delay', () => {
        const retry = delayed({ retryAttempts: 1, apexJobStatus: null });
        expect(statusOf(retry).key).toBe('retry');
    });

    it('shows a run that is running again as running', () => {
        expect(statusOf(delayed({ apexJobStatus: 'Processing' })).key).toBe('run');
    });

    it('makes a chain that has not started delayed, with the start time', () => {
        const next = inMinutes(5);
        const summary = sequenceSummary(groupSteps([delayed({ nextAttemptAt: next })]));
        expect(summary.status).toBe('delayed');
        expect(summary.delayedUntil).toBe(next);
    });

    it('keeps a started chain running and says when the next step goes', () => {
        const next = inMinutes(5);
        const summary = sequenceSummary(
            groupSteps([
                step({ chainSequence: 1, customJobId: 'a', status: 'COMPLETED' }),
                delayed({ chainSequence: 2, customJobId: 'b', nextAttemptAt: next })
            ])
        );
        expect(summary.status).toBe('running');
        expect(summary.delayedUntil).toBe(next);
    });

    it('has no delay on a chain once the time has passed', () => {
        const summary = sequenceSummary(groupSteps([delayed({ nextAttemptAt: inMinutes(-1) })]));
        expect(summary.status).toBe('queued');
        expect(summary.delayedUntil).toBeNull();
    });

    it('lets row and chain agree the moment the delay is over, without a new poll', () => {
        const steps = [delayed({ nextAttemptAt: inMinutes(5) })];
        expect(groupSteps(steps)[0].status.key).toBe('delay');
        const later = Date.now() + 6 * 60000;
        const clock = jest.spyOn(Date, 'now').mockReturnValue(later);
        expect(groupSteps(steps)[0].status).toEqual({ key: 'wait', label: 'Queued' });
        expect(sequenceSummary(groupSteps(steps)).status).toBe('queued');
        clock.mockRestore();
    });

    it('sleeps until the time instead of polling', () => {
        const now = Date.now();
        const rows = groupSteps([delayed({ nextAttemptAt: new Date(now + 120000).toISOString() })]);
        expect(pollDelayFor(rows, now)).toBe(120000);
        expect(nextPollDelay(sequenceSummary(rows))).toBe(POLL.queued);
    });

    it('marks a delayed page and keeps the run going', () => {
        const next = inMinutes(5);
        const row = groupSteps([
            step({
                customJobId: 'p1',
                chunkRunId: 'p1',
                chunkPage: 1,
                chunkPages: 3,
                status: 'COMPLETED'
            }),
            delayed({
                customJobId: 'p2',
                chunkRunId: 'p1',
                chunkPage: 2,
                chunkPages: 3,
                nextAttemptAt: next
            })
        ])[0];
        expect(row.status.key).toBe('delay');
        expect(delayOf(row).until).toBe(next);
        expect(pageStripFor(row).summary).toBe('1 of 3 pages');
    });
});

describe('pageStripFor', () => {
    const pages = (count, failed = []) =>
        Array.from({ length: count }, (_, i) =>
            step({
                chainSequence: 1,
                customJobId: 'p' + i,
                chunkPage: i + 1,
                chunkPages: count,
                status: failed.includes(i + 1) ? 'FAILED' : i < 7 ? 'COMPLETED' : 'ENQUEUED'
            })
        );

    it('draws one square per page up to the cap', () => {
        const strip = pageStripFor({ pages: pages(12, [7]), step: { chunkPages: 12 } });
        expect(strip.squares).toHaveLength(12);
        expect(strip.squares[6].key).toBe('bad');
        expect(strip.summary).toBe('7 of 12 pages · 1 failed');
    });

    it('draws the pages that do not exist yet and counts none done while waiting', () => {
        const strip = pageStripFor({
            pages: [step({ chunkPage: 1, chunkPages: 8, status: 'ENQUEUED' })],
            step: { chunkPages: 8 }
        });
        expect(strip.squares.map(square => square.key)).toEqual(['wait', ...Array(7).fill('todo')]);
        expect(strip.squares.map(square => square.page)).toEqual([1, 2, 3, 4, 5, 6, 7, 8]);
        expect(strip.summary).toBe('0 of 8 pages');
    });

    it('names the page only while one is running', () => {
        const done = step({ chunkPage: 1, chunkPages: 8, status: 'COMPLETED' });
        const second = status =>
            step({ chunkPage: 2, chunkPages: 8, status: 'ENQUEUED', apexJobStatus: status });
        const stripWith = page =>
            pageStripFor({ pages: [done, page], step: { chunkPages: 8 } }).summary;
        expect(stripWith(second('Processing'))).toBe('page 2 of 8');
        expect(stripWith(second('Queued'))).toBe('1 of 8 pages');
    });

    it('switches to a summary bar above the cap', () => {
        const failed = [3, 9, 11, 20, 25, 31, 44, 50, 51, 52, 60, 61];
        const strip = pageStripFor({
            pages: pages(CAPS.pageSquares + 40, failed),
            step: { chunkPages: CAPS.pageSquares + 40 }
        });
        expect(strip.squares).toBeNull();
        expect(strip.percent).toBe(18);
    });
});

describe('failedPageGroups', () => {
    const page = (number, overrides = {}) =>
        step({
            customJobId: `p${number}`,
            chunkRunId: 'run',
            chunkPage: number,
            chunkPages: 20,
            ...overrides
        });
    const failed = (number, message) =>
        page(number, {
            status: 'FAILED',
            exceptionType: 'System.DmlException',
            exceptionMessage: message
        });

    it('groups failed pages sharing one error and keeps different errors apart', () => {
        const row = groupSteps([
            page(1),
            failed(9, 'UNABLE_TO_LOCK_ROW'),
            failed(3, 'UNABLE_TO_LOCK_ROW'),
            failed(5, 'Validation failed')
        ])[0];
        const { groups, moreFailed } = failedPageGroups(row);
        expect(groups.map(group => group.pages.map(item => item.chunkPage))).toEqual([[3, 9], [5]]);
        expect(groups[0].message).toBe('UNABLE_TO_LOCK_ROW');
        expect(groups[0].exceptionType).toBe('System.DmlException');
        expect(moreFailed).toBe(0);
    });

    it('lists ten failed pages and counts the rest', () => {
        const pages = Array.from({ length: 13 }, (_, index) => failed(index + 1, 'same'));
        const { groups, moreFailed } = failedPageGroups(groupSteps(pages)[0]);
        expect(groups[0].pages).toHaveLength(CAPS.failedPagesListed);
        expect(moreFailed).toBe(3);
    });
});

describe('rowKeyOf', () => {
    const rows = groupSteps([
        step({ chainSequence: 1, customJobId: 'job' }),
        step({ chainSequence: 2, customJobId: 'p1', chunkRunId: 'run', chunkPage: 1 }),
        step({ chainSequence: 3, customJobId: 'p2', chunkRunId: 'run', chunkPage: 2 })
    ]);

    it('finds a job row and the chunk row owning any of its pages', () => {
        expect(rowKeyOf(rows, 'job')).toBe('job');
        expect(rowKeyOf(rows, 'p2')).toBe('p1');
    });

    it('finds nothing for an unknown job or no job', () => {
        expect(rowKeyOf(rows, 'gone')).toBeNull();
        expect(rowKeyOf(rows, null)).toBeNull();
    });
});

describe('pluralOf', () => {
    it('matches the word to the count', () => {
        expect(pluralOf(1, 'page')).toBe('1 page');
        expect(pluralOf(2, 'page')).toBe('2 pages');
        expect(pluralOf(0, 'page')).toBe('0 pages');
    });

    it('reads right for a one page run in the strip summary', () => {
        const row = groupSteps([
            step({ customJobId: 'p1', chunkRunId: 'run', chunkPage: 1, chunkPages: 1 })
        ])[0];
        expect(pageStripFor(row).summary).toBe('1 of 1 page');
    });
});

describe('truncate', () => {
    it('cuts long text at the cap with an ellipsis and leaves short text alone', () => {
        expect(truncate('x'.repeat(400), CAPS.exceptionChars)).toHaveLength(
            CAPS.exceptionChars + 1
        );
        expect(truncate('short', 300)).toBe('short');
        expect(truncate(null, 300)).toBe('');
    });
});

describe('sameData', () => {
    it('treats two objects with equal content as the same', () => {
        const row = { key: 'a', step: { id: '1', status: 'COMPLETED' }, status: { key: 'ok' } };
        expect(sameData(row, JSON.parse(JSON.stringify(row)))).toBe(true);
    });

    it('sees a changed nested value', () => {
        const row = { key: 'a', step: { id: '1', status: 'ENQUEUED' } };
        expect(sameData(row, { key: 'a', step: { id: '1', status: 'COMPLETED' } })).toBe(false);
    });

    it('handles undefined on either side', () => {
        expect(sameData(undefined, undefined)).toBe(true);
        expect(sameData(undefined, { key: 'a' })).toBe(false);
    });
});

describe('sequenceSummary lifecycle', () => {
    const page = (n, extra = {}) =>
        step({ chainSequence: 1, chunkRunId: 'run-1', chunkPage: n, chunkPages: 10, ...extra });

    it('is queued only while nothing has started', () => {
        const queued = sequenceSummary(
            groupSteps([
                step({ chainSequence: 1, status: 'ENQUEUED', apexJobStatus: 'Queued' }),
                step({ chainSequence: 2, status: 'ENQUEUED' })
            ])
        );
        expect(queued.status).toBe('queued');
        expect(queued.activity).toBe('waiting');
    });

    it('stays running between steps once one has finished', () => {
        const between = sequenceSummary(
            groupSteps([
                step({ chainSequence: 1 }),
                step({ chainSequence: 2, status: 'ENQUEUED', apexJobStatus: 'Queued' })
            ])
        );
        expect(between.status).toBe('running');
        expect(between.activity).toBe('waiting');
    });

    it('reports what the chain is doing now', () => {
        const executing = sequenceSummary(
            groupSteps([
                step({ chainSequence: 1, status: 'ENQUEUED', apexJobStatus: 'Processing' })
            ])
        );
        expect(executing.activity).toBe('executing');
        const retrying = sequenceSummary(
            groupSteps([
                step({
                    chainSequence: 1,
                    status: 'ENQUEUED',
                    retryAttempts: 1,
                    nextAttemptAt: '2026-11-02T10:05:00.000Z'
                })
            ])
        );
        expect(retrying.activity).toBe('retrying');
    });

    it('counts finished pages as started, so a chunk run with a queued page is running, not queued', () => {
        const rows = groupSteps([
            page(1),
            page(2),
            page(3, { status: 'ENQUEUED', apexJobStatus: 'Queued' })
        ]);
        expect(sequenceSummary(rows).status).toBe('running');
        const nothingYet = groupSteps([page(1, { status: 'ENQUEUED', apexJobStatus: 'Queued' })]);
        expect(sequenceSummary(nothingYet).status).toBe('queued');
    });

    it('keeps a chunk run running while pages are missing, even with a failed page and nothing in flight', () => {
        const rows = groupSteps([page(1), page(2, { status: 'FAILED' }), page(3)]);
        const summary = sequenceSummary(rows, Date.parse('2026-11-02T10:00:30.000Z'));
        expect(summary.status).toBe('running');
        expect(summary.failedSteps).toBe(1);
    });

    it('counts failed pages and failed jobs for the badge tail', () => {
        const rows = groupSteps([
            page(1, { status: 'FAILED' }),
            page(2, { status: 'FAILED' }),
            page(3),
            step({ chainSequence: 2, status: 'FAILED' })
        ]);
        expect(sequenceSummary(rows).failedSteps).toBe(3);
    });

    it('treats a chunk run with missing pages as finished once it has been quiet for ten minutes', () => {
        const rows = groupSteps([
            page(1, { finishedAt: '2026-11-02T10:00:00.000Z' }),
            page(2, { status: 'FAILED', finishedAt: '2026-11-02T10:00:05.000Z' })
        ]);
        const stale = sequenceSummary(rows, Date.parse('2026-11-02T10:11:00.000Z'));
        expect(stale.status).toBe('failed');
        const fresh = sequenceSummary(rows, Date.parse('2026-11-02T10:05:00.000Z'));
        expect(fresh.status).toBe('running');
    });

    it('finishes a chunk run when every page is there or the run was stopped', () => {
        const all = groupSteps([...Array(10).keys()].map(i => page(i + 1)));
        expect(sequenceSummary(all).status).toBe('completed');
        const stopped = groupSteps([
            page(1),
            page(2, { status: 'FAILED' }),
            page(3, { status: 'SKIPPED_CHUNK_STOPPED' })
        ]);
        expect(sequenceSummary(stopped).status).toBe('failed');
    });
});

describe('statusOf finalizer gap', () => {
    it('shows an enqueued step whose platform job failed as finishing, not failed', () => {
        expect(statusOf({ status: 'ENQUEUED', apexJobStatus: 'Failed' })).toEqual({
            key: 'run',
            label: 'Finishing'
        });
        expect(statusOf({ status: 'ENQUEUED', apexJobStatus: 'Aborted' }).key).toBe('bad');
    });
});

describe('progressOf', () => {
    it('lets chunk pages drive the chain progress', () => {
        const page = (n, extra = {}) =>
            step({ chainSequence: 2, chunkRunId: 'run-1', chunkPage: n, chunkPages: 10, ...extra });
        const rows = groupSteps([
            step({ chainSequence: 1 }),
            page(1),
            page(2, { status: 'FAILED' }),
            page(3, { status: 'ENQUEUED', apexJobStatus: 'Processing' })
        ]);
        const progress = sequenceSummary(rows).progress;
        expect(progress).toMatchObject({
            total: 11,
            completed: 2,
            failed: 1,
            running: 1,
            pending: 7,
            steps: 2,
            stepsCompleted: 1,
            pages: 10,
            pagesDone: 2,
            percent: 18
        });
    });
});

describe('progressOf after the chunk run', () => {
    it('counts a finished chunk run as one step once plain steps exist', () => {
        const page = (n, extra = {}) =>
            step({ chainSequence: 2, chunkRunId: 'run-1', chunkPage: n, chunkPages: 2, ...extra });
        const rows = groupSteps([
            step({ chainSequence: 1 }),
            page(1),
            page(2, { status: 'FAILED' })
        ]);
        expect(sequenceSummary(rows).progress).toMatchObject({
            total: 2,
            steps: 2,
            stepsCompleted: 1,
            failed: 1,
            pages: 0
        });
    });

    it('keeps pages for a chain that is only a chunk run', () => {
        const page = (n, extra = {}) =>
            step({ chainSequence: 1, chunkRunId: 'run-1', chunkPage: n, chunkPages: 2, ...extra });
        const rows = groupSteps([page(1), page(2, { status: 'FAILED' })]);
        expect(sequenceSummary(rows).progress).toMatchObject({ pages: 2, pagesDone: 2, failed: 1 });
    });
});

describe('groupSteps cache', () => {
    it('returns the same rows for the same steps and fresh rows for new steps', () => {
        const steps = [step({ chainSequence: 1 })];
        const rows = groupSteps(steps);
        expect(groupSteps(steps)).toBe(rows);
        expect(groupSteps([...steps])).not.toBe(rows);
    });

    it('still handles missing steps', () => {
        expect(groupSteps(undefined)).toEqual([]);
    });
});
