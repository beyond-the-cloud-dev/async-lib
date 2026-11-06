import { createElement } from 'lwc';
import AsyncJobStep from 'c/asyncJobStep';
import { groupSteps, CAPS } from 'c/asyncJobTimelineModel';
import { step, flushPromises } from '../../asyncJobTimeline/__tests__/data/fixtures';

class StepPO {
    constructor(el) {
        this.el = el;
    }
    byId(id) {
        return this.el.shadowRoot.querySelector(`[data-id="${id}"]`);
    }
    all(selector) {
        return [...this.el.shadowRoot.querySelectorAll(selector)];
    }
}

const rowOf = (steps, index = 0) => groupSteps(steps)[index];

const mount = async (row, props = {}) => {
    const el = createElement('c-async-job-step', { is: AsyncJobStep });
    el.row = row;
    el.nameByCustomJobId = { c1: 'Create invoice' };
    el.canRequeue = true;
    Object.assign(el, props);
    document.body.appendChild(el);
    await flushPromises();
    return new StepPO(el);
};

describe('c-async-job-step', () => {
    afterEach(() => {
        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
    });

    it('renders glyph, name and status for a completed job, with the class behind details', async () => {
        const po = await mount(
            rowOf([
                step({ chainSequence: 1, jobName: 'Reserve stock', className: 'ReserveStockJob' })
            ])
        );
        expect(po.byId('glyph').dataset.key).toBe('ok');
        expect(po.byId('name').textContent).toContain('Reserve stock');
        expect(po.byId('name').title).toContain('ReserveStockJob');
        expect(po.byId('class')).toBeNull();
        expect(po.byId('status').textContent).toBe('Completed');
        expect(po.byId('duration').textContent).toContain('2 s');
        po.byId('expand').click();
        await flushPromises();
        expect(po.byId('class').textContent).toContain('ReserveStockJob');
        expect(po.byId('details').textContent).toContain('job-');
    });

    it('shows the class as the name when the job has no name', async () => {
        const po = await mount(rowOf([step({ chainSequence: 1, jobName: null })]));
        expect(po.byId('name').textContent).toContain('StepJob');
    });

    it('shows at most two tags', async () => {
        const row = rowOf([
            step({
                chainSequence: 2,
                addedByCustomJobId: 'c1',
                priority: 1,
                dependencies: JSON.stringify([
                    { resolvedTargetCustomJobId: 'c1', requiredOutcome: 'SUCCESS' }
                ])
            })
        ]);
        const po = await mount(row);
        expect(po.all('[data-id="tags"] .tag')).toHaveLength(2);
    });

    it('expands a failed row into the exception box, truncates long messages and offers requeue', async () => {
        const po = await mount(
            rowOf([
                step({
                    chainSequence: 3,
                    status: 'FAILED',
                    exceptionType: 'System.DmlException',
                    exceptionMessage: 'x'.repeat(500),
                    retryAttempts: 2,
                    retryHistory: 'Attempt 1\nAttempt 2',
                    requeueStatus: 'Stored'
                })
            ])
        );
        expect(po.byId('failbox')).toBeNull();
        po.byId('expand').click();
        await flushPromises();
        expect(po.byId('failbox')).not.toBeNull();
        expect(po.byId('exception').textContent).toHaveLength(CAPS.exceptionChars + 1);
        po.byId('more').click();
        await flushPromises();
        expect(po.byId('exception').textContent).toHaveLength(500);
        expect(po.byId('attempt').textContent).toContain('attempt 3');
        expect(po.byId('requeue')).not.toBeNull();
    });

    describe('failed pages of a chunk run', () => {
        const chunkRunFailing = (failing, total = 15) =>
            rowOf(
                Array.from({ length: total }, (_, index) => {
                    const number = index + 1;
                    const failedOne = failing.includes(number);
                    return step({
                        id: `result-${number}`,
                        name: `AR-${number}`,
                        customJobId: `p${number}`,
                        chunkRunId: 'run',
                        chunkPage: number,
                        chunkPages: total,
                        status: failedOne ? 'FAILED' : 'COMPLETED',
                        exceptionType: failedOne ? 'System.DmlException' : undefined,
                        exceptionMessage: failedOne ? 'UNABLE_TO_LOCK_ROW' : undefined
                    });
                })
            );

        const opened = async row => {
            const po = await mount(row);
            po.byId('expand').click();
            await flushPromises();
            return po;
        };

        it('names a failed page and shows its own error, not a bare number', async () => {
            const po = await opened(chunkRunFailing([7]));
            expect(po.byId('failed-group-title').textContent).toBe('Page 7 failed');
            expect(po.byId('failed-group').textContent).toContain('System.DmlException');
            expect(po.byId('failed-group').textContent).toContain('UNABLE_TO_LOCK_ROW');
        });

        it('lists pages sharing an error in one sentence with a link to each result', async () => {
            const po = await opened(chunkRunFailing([3, 7, 9]));
            expect(po.byId('failed-group-title').textContent).toBe('Pages 3, 7, 9 failed');
            const links = po.all('[data-id="failed-page-result"]');
            expect(links.map(link => link.textContent)).toEqual(['AR-3', 'AR-7', 'AR-9']);
            expect(links[1].getAttribute('href')).toBe('/result-7');
        });

        it('says how many more failed above the listed cap', async () => {
            const failing = Array.from({ length: 13 }, (_, index) => index + 1);
            const po = await opened(chunkRunFailing(failing));
            expect(po.byId('failed-more').textContent).toBe('and 3 more failed');
        });

        it('does not repeat the error when the first page is the one that failed', async () => {
            const po = await opened(chunkRunFailing([1]));
            expect(po.byId('exception')).toBeNull();
            expect(po.all('[data-id="failed-group"]')).toHaveLength(1);
        });

        it('says the footer link opens the first page', async () => {
            const po = await opened(chunkRunFailing([7]));
            expect(po.byId('open-result').textContent).toBe('Open first page result AR-1');
        });
    });

    it('offers requeue as an icon too, firing the same event', async () => {
        const po = await mount(
            rowOf([step({ customJobId: 'x', status: 'FAILED', requeueStatus: 'Stored' })])
        );
        const handler = jest.fn();
        po.el.addEventListener('requeue', handler);
        const compact = po.byId('requeue-compact');
        expect(compact.iconName).toBe('utility:refresh');
        expect(compact.title).toBe('Requeue');
        compact.click();
        expect(handler).toHaveBeenCalledTimes(1);
    });

    describe('tags', () => {
        const dependent = (overrides = {}) =>
            rowOf([
                step({
                    customJobId: 'x',
                    addedByCustomJobId: 'c1',
                    priority: 1,
                    dependencies: JSON.stringify([
                        { resolvedTargetCustomJobId: 'c1', requiredOutcome: 'SUCCESS' }
                    ]),
                    ...overrides
                })
            ]);

        it('shows two tags and keeps the rest behind a count with their text on hover', async () => {
            const po = await mount(dependent());
            expect(po.all('[data-id="tags"] .tag')).toHaveLength(2);
            expect(po.byId('tags-more').textContent).toBe('+1');
            expect(po.byId('tags-more').title).toBe('P1');
        });

        it('shows no count when every tag fits', async () => {
            const po = await mount(dependent({ priority: null }));
            expect(po.byId('tags-more')).toBeNull();
        });

        it('announces the job a tag points at on hover and focus, and clears it after', async () => {
            const po = await mount(dependent());
            const targets = [];
            po.el.addEventListener('tagtarget', event => targets.push(event.detail.jobId));
            const tag = po.all('[data-id="tags"] .tag')[1];
            tag.dispatchEvent(new CustomEvent('mouseenter'));
            tag.dispatchEvent(new CustomEvent('mouseleave'));
            tag.dispatchEvent(new CustomEvent('focus'));
            tag.dispatchEvent(new CustomEvent('blur'));
            expect(targets).toEqual(['c1', null, 'c1', null]);
        });

        it('stays quiet on a tag that points at nothing', async () => {
            const po = await mount(rowOf([step({ customJobId: 'x', priority: 1 })]));
            const targets = [];
            po.el.addEventListener('tagtarget', event => targets.push(event.detail.jobId));
            po.all('[data-id="tags"] .tag')[0].dispatchEvent(new CustomEvent('mouseenter'));
            expect(targets).toEqual([]);
        });
    });

    it('marks the target of a hovered tag and the last row of the rail', async () => {
        const po = await mount(rowOf([step({ customJobId: 'x' })]), {
            isTarget: true,
            isLastRow: true
        });
        expect(po.byId('row').classList.contains('is-target')).toBe(true);
        expect(po.byId('row').classList.contains('is-last-row')).toBe(true);
    });

    it('fires requeue with the result id and a label on one click', async () => {
        const po = await mount(
            rowOf([
                step({
                    chainSequence: 3,
                    id: 'a0X',
                    jobName: 'Commission split',
                    status: 'FAILED',
                    requeueStatus: 'Stored'
                })
            ])
        );
        const handler = jest.fn();
        po.el.addEventListener('requeue', handler);
        po.byId('requeue').click();
        expect(handler.mock.calls[0][0].detail).toEqual({
            resultIds: ['a0X'],
            label: 'Commission split'
        });
    });

    it('explains why a failed row cannot be requeued instead of offering the button', async () => {
        const po = await mount(
            rowOf([step({ chainSequence: 3, status: 'FAILED', requeueStatus: 'TooLarge' })])
        );
        expect(po.byId('requeue')).toBeNull();
        expect(po.byId('warning').textContent).toContain('TooLarge');
    });

    it('marks an already requeued row without a warning or a button', async () => {
        const po = await mount(
            rowOf([step({ chainSequence: 3, status: 'FAILED', requeueStatus: 'Requeued' })])
        );
        expect(po.byId('requeue')).toBeNull();
        expect(po.byId('warning')).toBeNull();
        expect(po.all('[data-id="tags"] .tag')[0].textContent).toBe('requeued');
    });

    it('hides the requeue button while the chain is in flight', async () => {
        const po = await mount(
            rowOf([step({ chainSequence: 3, status: 'FAILED', requeueStatus: 'Stored' })]),
            { chainInFlight: true }
        );
        expect(po.byId('requeue')).toBeNull();
    });

    it('opens the details from anywhere on the row', async () => {
        const po = await mount(rowOf([step({ chainSequence: 1 })]));
        po.byId('row').click();
        await flushPromises();
        expect(po.byId('details')).not.toBeNull();
        po.byId('details').click();
        await flushPromises();
        expect(po.byId('details')).not.toBeNull();
    });

    it('hides the requeue button without permission', async () => {
        const po = await mount(
            rowOf([step({ chainSequence: 3, status: 'FAILED', requeueStatus: 'Stored' })]),
            { canRequeue: false }
        );
        expect(po.byId('requeue')).toBeNull();
    });

    it('shows three record chips as new-tab links and a +N expander', async () => {
        const records = Array.from({ length: 7 }, (_, i) => ({
            key: '00' + i,
            name: 'Rec ' + i,
            objectName: 'Account',
            source: 'Salesforce'
        }));
        const po = await mount(rowOf([step({ chainSequence: 1, records })]));
        expect(po.all('[data-id="chips"] .chip')).toHaveLength(CAPS.chips);
        expect(po.all('[data-id="chips"] .chip')[0].getAttribute('href')).toBe('/000');
        expect(po.all('[data-id="chips"] .chip')[0].getAttribute('target')).toBe('_blank');
        expect(po.byId('chips-more').textContent).toContain('+4');
        po.byId('chips-more').click();
        await flushPromises();
        expect(po.all('[data-id="chips"] .chip')).toHaveLength(7);
    });

    it('shows a record from another system as a plain chip naming object and key', async () => {
        const records = [
            { key: '4711', source: 'NetSuite', objectName: 'Customer', name: '4711' },
            { key: '4712', source: null, objectName: null, name: '4712' }
        ];
        const po = await mount(rowOf([step({ chainSequence: 1, records })]));
        const chips = po.all('[data-id="chips"] .chip');
        expect(chips.map(chip => chip.tagName)).toEqual(['SPAN', 'SPAN']);
        expect(chips.map(chip => chip.textContent)).toEqual(['Customer 4711', '4712']);
        expect(chips.map(chip => chip.getAttribute('title'))).toEqual([
            'NetSuite Customer',
            'Record in another system'
        ]);
    });

    it('hides the chip of the record whose page shows the card', async () => {
        const records = [
            {
                key: '001000000000001AAA',
                name: 'Order #10248',
                objectName: 'Account',
                source: 'Salesforce'
            },
            {
                key: '003000000000001AAA',
                name: 'Jane Doe',
                objectName: 'Contact',
                source: 'Salesforce'
            }
        ];
        const po = await mount(rowOf([step({ chainSequence: 1, records })]), {
            pageRecordId: '001000000000001AAA'
        });
        expect(po.all('[data-id="chips"] .chip').map(chip => chip.textContent)).toEqual([
            'Jane Doe'
        ]);
        expect(po.byId('chips-more')).toBeNull();
        const only = await mount(
            rowOf([step({ chainSequence: 1, records: records.slice(0, 1) })]),
            { pageRecordId: '001000000000001AAA' }
        );
        expect(only.byId('chips')).toBeNull();
    });

    it('shows only the planned delay until the job is enqueued', async () => {
        const po = await mount(rowOf([step({ status: 'ENQUEUED', delayMinutes: 10 })]));
        expect(po.byId('status').textContent).toBe('Enqueued');
        expect(po.byId('delay-planned').textContent).toBe('delay 10 min');
        expect(po.byId('delay-until')).toBeNull();
    });

    it('shows the time and no platform text while the delay runs out', async () => {
        const po = await mount(
            rowOf([
                step({
                    status: 'ENQUEUED',
                    apexJobStatus: 'Queued',
                    delayMinutes: 10,
                    nextAttemptAt: new Date(Date.now() + 300000).toISOString()
                })
            ])
        );
        expect(po.byId('status').textContent).toBe('Delayed');
        expect(po.byId('delay-until')).not.toBeNull();
        expect(po.byId('delay-planned')).toBeNull();
        expect(po.byId('platform')).toBeNull();
        expect(po.byId('glyph').dataset.key).toBe('delay');
    });

    it('says the job waits in the queue, not the flex queue, when plainly queued', async () => {
        const po = await mount(rowOf([step({ status: 'ENQUEUED', apexJobStatus: 'Queued' })]));
        expect(po.byId('platform').textContent).toBe('waiting in the queue');
    });

    it('lists the delay in the details', async () => {
        const po = await mount(rowOf([step({ status: 'COMPLETED', delayMinutes: 10 })]));
        po.byId('expand').click();
        await flushPromises();
        expect(po.byId('details').textContent).toContain('Delay10 min');
    });

    it('times a chunk run from its first start to its last finish', async () => {
        const page = (number, startedAt, finishedAt) =>
            step({
                chainSequence: 2,
                customJobId: 'p' + number,
                chunkRunId: 'p1',
                chunkPage: number,
                chunkPages: 2,
                status: 'COMPLETED',
                startedAt,
                finishedAt
            });
        const startOfRun = '2026-11-06T10:00:00.000Z';
        const endOfRun = '2026-11-06T10:00:26.000Z';
        const po = await mount(
            rowOf([
                page(1, startOfRun, '2026-11-06T10:00:05.000Z'),
                page(2, '2026-11-06T10:00:06.000Z', endOfRun)
            ])
        );
        po.byId('expand').click();
        await flushPromises();
        const shown = iso =>
            new Date(iso).toLocaleString(undefined, {
                day: 'numeric',
                month: 'short',
                hour: '2-digit',
                minute: '2-digit',
                second: '2-digit'
            });
        const details = po.byId('details').textContent;
        expect(details).toContain(`Started${shown(startOfRun)}`);
        expect(details).toContain(`Finished${shown(endOfRun)}`);
    });

    it('shows no finish while a chunk run still has pages to go', async () => {
        const po = await mount(
            rowOf([
                step({
                    customJobId: 'p1',
                    chunkRunId: 'p1',
                    chunkPage: 1,
                    chunkPages: 2,
                    status: 'COMPLETED',
                    startedAt: '2026-11-06T10:00:00.000Z',
                    finishedAt: '2026-11-06T10:00:05.000Z'
                })
            ])
        );
        po.byId('expand').click();
        await flushPromises();
        expect(po.byId('details').textContent).not.toContain('Finished');
    });

    it('draws a page strip for a chunk run and a bar above the cap', async () => {
        const pages = n =>
            Array.from({ length: n }, (_, i) =>
                step({
                    chainSequence: 2,
                    customJobId: 'p' + i,
                    chunkRunId: 'p0',
                    chunkPage: i + 1,
                    chunkPages: n,
                    status: i < 3 ? 'COMPLETED' : 'ENQUEUED'
                })
            );
        const small = await mount(rowOf(pages(12)));
        expect(small.all('[data-id="strip"] i')).toHaveLength(12);
        expect(small.byId('strip-summary').textContent).toContain('3 of 12 pages');
        const big = await mount(rowOf(pages(CAPS.pageSquares + 1)));
        expect(big.byId('strip')).toBeNull();
        expect(big.byId('strip-bar')).not.toBeNull();
    });

    it('renders a running row with a spinner glyph and the platform job id', async () => {
        const po = await mount(
            rowOf([
                step({
                    chainSequence: 2,
                    status: 'ENQUEUED',
                    apexJobStatus: 'Processing',
                    salesforceJobId: '707000000000001AAA',
                    finishedAt: null
                })
            ])
        );
        expect(po.byId('glyph').dataset.key).toBe('run');
        expect(po.byId('status').textContent).toBe('Running');
        expect(po.byId('platform').textContent).toContain('on the platform');
        expect(po.byId('platform').title).toContain('707000000000001AAA');
    });

    it('explains a finishing step and spaces the next attempt of a retry', async () => {
        const finishing = await mount(
            rowOf([
                step({
                    chainSequence: 2,
                    status: 'ENQUEUED',
                    apexJobStatus: 'Completed',
                    salesforceJobId: '707000000000001AAA',
                    finishedAt: null
                })
            ])
        );
        expect(finishing.byId('status').textContent).toBe('Finishing');
        expect(finishing.byId('platform').textContent).toContain('result pending');
        const retrying = await mount(
            rowOf([
                step({
                    chainSequence: 2,
                    status: 'ENQUEUED',
                    retryAttempts: 1,
                    nextAttemptAt: '2026-11-02T09:10:00.000Z',
                    finishedAt: null
                })
            ])
        );
        expect(retrying.byId('next-attempt').textContent).toContain('next attempt\u00a0');
    });

    it('unions the records of every chunk page into the chips', async () => {
        const order = {
            key: '001000000000001AAA',
            name: 'Order',
            objectName: 'Account',
            source: 'Salesforce'
        };
        const pages = [1, 2].map(n =>
            step({
                chainSequence: 2,
                customJobId: 'pg' + n,
                chunkRunId: 'run',
                chunkPage: n,
                chunkPages: 2,
                records: [
                    order,
                    {
                        key: '00100000000009' + n + 'AAA',
                        name: 'Line ' + n,
                        objectName: 'Account',
                        source: 'Salesforce'
                    }
                ]
            })
        );
        const po = await mount(rowOf(pages));
        expect(po.all('[data-id="chips"] .chip').map(chip => chip.textContent)).toEqual([
            'Order',
            'Line 1',
            'Line 2'
        ]);
    });

    it('opens the details from the name row, but not from a record chip', async () => {
        const records = [
            {
                key: '001000000000001AAA',
                name: 'Order',
                objectName: 'Account',
                source: 'Salesforce'
            }
        ];
        const po = await mount(rowOf([step({ chainSequence: 1, records })]));
        po.byId('name-line').click();
        await flushPromises();
        expect(po.byId('details')).not.toBeNull();
        po.all('[data-id="chips"] .chip')[0].dispatchEvent(
            new MouseEvent('click', { bubbles: true, cancelable: true })
        );
        await flushPromises();
        expect(po.byId('details')).not.toBeNull();
    });

    it('offers a link to the replay of a requeued row', async () => {
        const po = await mount(
            rowOf([
                step({
                    chainSequence: 3,
                    status: 'FAILED',
                    requeueStatus: 'Requeued',
                    replayResultId: 'a0X000000000002AAA',
                    replayChainId: 'chain-replay'
                })
            ])
        );
        const handler = jest.fn();
        po.el.addEventListener('openreplay', handler);
        po.byId('open-replay').click();
        expect(handler.mock.calls[0][0].detail).toEqual({
            resultId: 'a0X000000000002AAA',
            chainId: 'chain-replay'
        });
    });

    it('applies new, changed and current classes', async () => {
        const po = await mount(rowOf([step({ chainSequence: 2, status: 'ENQUEUED' })]), {
            isNew: true,
            isChanged: true,
            isCurrent: true
        });
        const root = po.byId('row');
        expect(root.classList.contains('is-new')).toBe(true);
        expect(root.classList.contains('is-changed')).toBe(true);
        expect(root.classList.contains('is-current')).toBe(true);
        expect(po.byId('new-badge')).not.toBeNull();
    });

    it('indents a finalizer under its parent', async () => {
        const rows = groupSteps([
            step({ chainSequence: 1, customJobId: 'c1' }),
            step({ chainSequence: 1, customJobId: 'f', parentCustomJobId: 'c1', jobName: 'Audit' })
        ]);
        const po = await mount(rows[1]);
        expect(po.byId('row').classList.contains('is-sub')).toBe(true);
        expect(po.byId('glyph').classList.contains('glyph')).toBe(true);
        expect(po.all('[data-id="tags"] .tag')[0].textContent).toContain(
            'finalizer of Create invoice'
        );
    });
});
