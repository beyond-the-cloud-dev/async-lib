import { createElement } from 'lwc';
import AsyncJobSequence from 'c/asyncJobSequence';
import { CAPS } from 'c/asyncJobTimelineModel';
import {
    step,
    sequence,
    failedSequence,
    runningSequence,
    completedSequence,
    longSequence,
    flushPromises
} from '../../asyncJobTimeline/__tests__/data/fixtures';

class SequencePO {
    constructor(el) {
        this.el = el;
    }
    byId(id) {
        return this.el.shadowRoot.querySelector(`[data-id="${id}"]`);
    }
    get steps() {
        return [...this.el.shadowRoot.querySelectorAll('c-async-job-step')];
    }
    get gaps() {
        return [...this.el.shadowRoot.querySelectorAll('[data-id="gap"]')];
    }
}

const mount = async (chain, props = {}) => {
    const el = createElement('c-async-job-sequence', { is: AsyncJobSequence });
    el.sequence = chain;
    el.canRequeue = true;
    el.defaultExpanded = true;
    Object.assign(el, props);
    document.body.appendChild(el);
    await flushPromises();
    return new SequencePO(el);
};

describe('c-async-job-sequence', () => {
    afterEach(() => {
        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
    });

    it('expands a failed sequence with badge, progress and a requeue button counting replayable rows', async () => {
        const po = await mount(failedSequence());
        expect(po.byId('badge').textContent).toBe('Failed');
        expect(po.byId('progress-text').textContent).toContain('2 of 5');
        expect(po.steps).toHaveLength(5);
        expect(po.byId('requeue-failed').label).toContain('2');
    });

    it('matches the words to a count of one', async () => {
        const po = await mount(
            sequence('one', [
                step({
                    chainSequence: 1,
                    customJobId: 'a',
                    status: 'FAILED',
                    requeueStatus: 'Stored'
                })
            ])
        );
        expect(po.byId('requeue-failed').label).toBe('Requeue failed step (1)');
        expect(po.byId('progress-text').textContent).toContain('0 of 1 step completed');
    });

    it('says one hidden step in the singular', async () => {
        const steps = Array.from({ length: CAPS.stepsCollapsed + 1 }, (_, index) =>
            step({
                chainSequence: index + 1,
                customJobId: `s${index}`,
                status: index === 3 ? 'COMPLETED' : 'FAILED'
            })
        );
        const po = await mount(sequence('gap', steps));
        expect(po.gaps[0].textContent.trim()).toBe('1 completed step hidden · Show');
    });

    describe('compact layout controls', () => {
        it('offers requeue as a short count with the full text on hover', async () => {
            const po = await mount(failedSequence());
            const compact = po.byId('requeue-failed-compact');
            expect(compact.label).toBe('2');
            expect(compact.iconName).toBe('utility:refresh');
            expect(compact.title).toBe(po.byId('requeue-failed').label);
        });

        it('starts the same requeue from the compact button', async () => {
            const po = await mount(failedSequence());
            const handler = jest.fn();
            po.el.addEventListener('requeue', handler);
            po.byId('requeue-failed-compact').click();
            expect(handler).toHaveBeenCalledTimes(1);
        });
    });

    describe('collapsed progress', () => {
        const jobs = count =>
            Array.from({ length: count }, (_, index) =>
                step({ chainSequence: index + 1, customJobId: `j${index}` })
            );
        const chunk = (id, at) =>
            step({
                chainSequence: at,
                customJobId: id,
                chunkRunId: id,
                chunkPage: 1,
                chunkPages: 1
            });
        const collapsed = chain => mount(chain, { defaultExpanded: false });

        it('shows every job as a dot while they all fit', async () => {
            const po = await collapsed(sequence('fit', jobs(CAPS.dots)));
            expect(po.el.shadowRoot.querySelectorAll('[data-id="dots"] i')).toHaveLength(CAPS.dots);
            expect(po.byId('mini-progress')).toBeNull();
        });

        it('switches to a bar when the jobs do not fit, with no partial dots', async () => {
            const po = await collapsed(sequence('over', jobs(CAPS.dots + 1)));
            expect(po.byId('dots')).toBeNull();
            expect(po.byId('mini-progress').textContent).toContain('100 %');
            expect(
                po.el.shadowRoot.querySelectorAll('[data-id="mini-progress"] .seg-ok')
            ).toHaveLength(1);
        });

        it('counts a chunk strip as three dots when deciding what fits', async () => {
            const fits = [...jobs(CAPS.dots - CAPS.dotsPerChunk), chunk('c', 99)];
            expect((await collapsed(sequence('fits', fits))).byId('dots')).not.toBeNull();
            const over = [...jobs(CAPS.dots - CAPS.dotsPerChunk + 1), chunk('c', 99)];
            expect((await collapsed(sequence('over', over))).byId('dots')).toBeNull();
        });

        it('adds up several chunks and jobs', async () => {
            const over = [
                ...jobs(CAPS.dots - 2 * CAPS.dotsPerChunk + 1),
                chunk('c1', 90),
                chunk('c2', 91)
            ];
            expect((await collapsed(sequence('over', over))).byId('mini-progress')).not.toBeNull();
        });

        it('gives a chain of only chunk runs the bar', async () => {
            const po = await collapsed(sequence('pages', [chunk('c', 1)]));
            expect(po.byId('dots')).toBeNull();
            expect(po.byId('mini-progress')).not.toBeNull();
        });
    });

    describe('rail and tag targets', () => {
        const dependent = () =>
            sequence('deps', [
                step({ chainSequence: 1, customJobId: 'first', status: 'FAILED' }),
                step({ chainSequence: 2, customJobId: 'second', status: 'FAILED' }),
                step({
                    chainSequence: 3,
                    customJobId: 'third',
                    status: 'FAILED',
                    dependencies: JSON.stringify([
                        { resolvedTargetCustomJobId: 'first', requiredOutcome: 'SUCCESS' }
                    ])
                })
            ]);

        it('tells only the last step that the rail ends there', async () => {
            const po = await mount(dependent());
            expect(po.steps.map(item => item.isLastRow)).toEqual([false, false, true]);
        });

        it('marks the job a tag points at and clears it when the tag lets go', async () => {
            const po = await mount(dependent());
            po.steps[2].dispatchEvent(new CustomEvent('tagtarget', { detail: { jobId: 'first' } }));
            await flushPromises();
            expect(po.steps.map(item => item.isTarget)).toEqual([true, false, false]);
            po.steps[2].dispatchEvent(new CustomEvent('tagtarget', { detail: { jobId: null } }));
            await flushPromises();
            expect(po.steps.map(item => item.isTarget)).toEqual([false, false, false]);
        });
    });

    it('stays collapsed unless told otherwise, even when failed', async () => {
        const po = await mount(failedSequence(), { defaultExpanded: false });
        expect(po.steps).toHaveLength(0);
        po.el.expand();
        await flushPromises();
        expect(po.steps).toHaveLength(5);
    });

    it('collapses a completed sequence into one line with a dot per step', async () => {
        const po = await mount(completedSequence(), { defaultExpanded: false });
        expect(po.steps).toHaveLength(0);
        expect(po.byId('badge').textContent).toBe('Completed');
        expect(po.el.shadowRoot.querySelectorAll('[data-id="dots"] i')).toHaveLength(3);
        expect(po.byId('started').title).toContain('2026');
        po.byId('toggle').click();
        await flushPromises();
        expect(po.steps).toHaveLength(3);
    });

    it('toggles from the header row but not from its action buttons', async () => {
        const po = await mount(completedSequence(), { defaultExpanded: false });
        po.byId('head').click();
        await flushPromises();
        expect(po.steps).toHaveLength(3);
        po.byId('actions').click();
        await flushPromises();
        expect(po.steps).toHaveLength(3);
        po.byId('head').click();
        await flushPromises();
        expect(po.steps).toHaveLength(0);
    });

    it('hides expanded gaps again after a collapse', async () => {
        const po = await mount(longSequence(30, 17));
        po.gaps[0].click();
        await flushPromises();
        expect(po.steps).toHaveLength(19);
        po.byId('toggle').click();
        await flushPromises();
        po.byId('toggle').click();
        await flushPromises();
        expect(po.steps).toHaveLength(6);
        expect(po.gaps).toHaveLength(2);
    });

    it('shows running state with elapsed time and no requeue button', async () => {
        const po = await mount(runningSequence());
        expect(po.byId('badge').textContent).toBe('Running');
        expect(po.byId('subline').textContent).toMatch(/running \d/);
        expect(po.byId('requeue-failed')).toBeNull();
        expect(po.steps[0].isCurrent).toBe(false);
        expect(po.steps[1].isCurrent).toBe(true);
        expect(po.steps[2].isCurrent).toBe(false);
    });

    it('says queued for while nothing has started and marks the step the platform holds', async () => {
        const queued = runningSequence();
        queued.steps[0].status = 'ENQUEUED';
        queued.steps[1].apexJobStatus = 'Queued';
        const po = await mount(queued);
        expect(po.byId('badge').textContent).toBe('Queued');
        expect(po.byId('badge').querySelector('.mark-hollow')).not.toBeNull();
        expect(po.byId('subline').textContent).toMatch(/queued for \d/);
        expect(po.steps[1].isCurrent).toBe(true);
        expect(po.steps[2].isCurrent).toBe(false);
    });

    it('shows a chain that has not started as delayed, with its start time', async () => {
        const seq = runningSequence();
        seq.steps.forEach(item => {
            item.status = 'ENQUEUED';
            item.apexJobStatus = null;
            item.startedAt = null;
            item.finishedAt = null;
        });
        seq.steps[0].apexJobStatus = 'Queued';
        seq.steps[0].nextAttemptAt = new Date(Date.now() + 300000).toISOString();
        const po = await mount(seq);
        expect(po.byId('badge').textContent).toBe('Delayed');
        expect(po.byId('badge-delayed')).toBeNull();
        expect(po.byId('badge').classList.contains('chain-badge-delayed')).toBe(true);
        expect(po.byId('subline').textContent).toContain('starts at');
        expect(po.byId('subline').textContent).not.toContain('queued for');
    });

    it('adds Delayed to a running chain and says when the next step goes', async () => {
        const seq = runningSequence();
        const next = seq.steps[seq.steps.length - 1];
        seq.steps.forEach(item => {
            item.status = 'COMPLETED';
            item.apexJobStatus = null;
        });
        Object.assign(next, {
            status: 'ENQUEUED',
            apexJobStatus: 'Queued',
            finishedAt: null,
            nextAttemptAt: new Date(Date.now() + 300000).toISOString()
        });
        const po = await mount(seq);
        expect(po.byId('badge').textContent).toContain('Running');
        expect(po.byId('badge-delayed').textContent).toBe('Delayed');
        expect(po.byId('subline').textContent).toContain('next step at');
        expect(po.byId('subline').textContent).not.toContain('running');
    });

    it('keeps the failure count next to Delayed on a running chain', async () => {
        const seq = runningSequence();
        const next = seq.steps[seq.steps.length - 1];
        seq.steps.forEach(item => {
            item.status = 'COMPLETED';
            item.apexJobStatus = null;
        });
        seq.steps[0].status = 'FAILED';
        Object.assign(next, {
            status: 'ENQUEUED',
            apexJobStatus: 'Queued',
            finishedAt: null,
            nextAttemptAt: new Date(Date.now() + 300000).toISOString()
        });
        const po = await mount(seq);
        expect(po.byId('badge').textContent).toContain('Running');
        expect(po.byId('badge-failed').textContent).toBe('1');
        expect(po.byId('badge-delayed').textContent).toBe('Delayed');
    });

    it('stays running between steps with a hollow mark once a step has finished', async () => {
        const between = runningSequence();
        between.steps[1].apexJobStatus = 'Queued';
        const po = await mount(between);
        expect(po.byId('badge').textContent).toBe('Running');
        expect(po.byId('badge').querySelector('.mark-hollow')).not.toBeNull();
        expect(po.byId('badge').title).toBe('Running · waiting for the platform');
        expect(po.byId('badge-failed')).toBeNull();
    });

    it('pulses a dot while a step executes and counts failures so far in a red tail', async () => {
        const running = runningSequence();
        running.steps[0].status = 'FAILED';
        const po = await mount(running);
        expect(po.byId('badge').querySelector('.mark-dot')).not.toBeNull();
        expect(po.byId('badge-failed').textContent).toBe('1');
        expect(po.byId('badge').title).toBe('Running · a step is executing · 1 failed so far');
    });

    it('shows the refresh mark while a retry waits', async () => {
        const retrying = runningSequence();
        retrying.steps[1].apexJobStatus = undefined;
        retrying.steps[1].retryAttempts = 1;
        retrying.steps[1].nextAttemptAt = new Date(Date.now() + 60000).toISOString();
        const po = await mount(retrying);
        expect(po.byId('badge').querySelector('svg.mark-svg')).not.toBeNull();
        expect(po.byId('badge').title).toBe('Running · waiting for a retry');
    });

    it('hands the page record id to every step', async () => {
        const po = await mount(completedSequence(), { pageRecordId: '001000000000001AAA' });
        expect(po.steps.every(row => row.pageRecordId === '001000000000001AAA')).toBe(true);
    });

    it('marks no step current once the chain settled', async () => {
        const po = await mount(completedSequence());
        expect(po.steps.some(row => row.isCurrent)).toBe(false);
    });

    it('reports how far its header moved once the toggle rendered', async () => {
        const po = await mount(completedSequence(), { defaultExpanded: false });
        const handler = jest.fn();
        po.el.addEventListener('sequencetoggle', handler);
        po.el.getBoundingClientRect = jest
            .fn()
            .mockReturnValueOnce({ top: 300 })
            .mockReturnValueOnce({ top: 180 });
        po.byId('head').click();
        await flushPromises();
        expect(handler).toHaveBeenCalledTimes(1);
        expect(handler.mock.calls[0][0].detail).toEqual({ open: true, delta: -120 });
        expect(po.steps).toHaveLength(3);
    });

    it('hides requeue while the chain is still in flight', async () => {
        const live = failedSequence();
        live.steps[4].status = 'ENQUEUED';
        live.steps[4].apexJobStatus = 'Queued';
        const po = await mount(live);
        expect(po.byId('requeue-failed')).toBeNull();
        expect(po.steps[2].chainInFlight).toBe(true);
    });

    it('hides the requeue button without permission', async () => {
        const po = await mount(failedSequence(), { canRequeue: false });
        expect(po.byId('requeue-failed')).toBeNull();
    });

    it('fires one requeue event with every replayable id and a label, from a button group', async () => {
        const po = await mount(failedSequence());
        const handler = jest.fn();
        po.el.addEventListener('requeue', handler);
        expect(po.el.shadowRoot.querySelector('lightning-button-group')).not.toBeNull();
        expect(po.byId('requeue-failed').variant).toBe('brand-outline');
        po.byId('requeue-failed').click();
        await flushPromises();
        expect(handler).toHaveBeenCalledTimes(1);
        expect(handler.mock.calls[0][0].detail.resultIds).toHaveLength(2);
        expect(handler.mock.calls[0][0].detail.label).toContain('2 failed steps');
    });

    it('folds long completed runs into gaps that expand on click', async () => {
        const po = await mount(longSequence(30, 17));
        expect(po.steps).toHaveLength(6);
        expect(po.gaps).toHaveLength(2);
        expect(po.gaps[0].textContent).toContain('13 completed steps');
        po.gaps[0].click();
        await flushPromises();
        expect(po.steps).toHaveLength(19);
    });

    it('caps a very long sequence and points to the results list', async () => {
        const po = await mount(longSequence(CAPS.stepsMax + 50, 5));
        po.gaps.forEach(gap => gap.click());
        await flushPromises();
        expect(po.steps.length).toBeLessThanOrEqual(CAPS.stepsMax);
        expect(po.byId('cap-note').textContent).toContain(
            `${CAPS.stepsMax} of ${CAPS.stepsMax + 50}`
        );
    });

    it('passes highlight flags down to the matching steps', async () => {
        const po = await mount(runningSequence(), {
            highlight: { added: ['r3'], changed: ['r2'] }
        });
        expect(po.steps[2].isNew).toBe(true);
        expect(po.steps[1].isChanged).toBe(true);
        expect(po.steps[0].isNew).toBe(false);
    });

    it('offers the chain map and the first result from the menu', async () => {
        const seq = failedSequence();
        const po = await mount(seq);
        const opened = jest.fn();
        const result = jest.fn();
        po.el.addEventListener('openmap', opened);
        po.el.addEventListener('openresult', result);
        po.byId('menu').dispatchEvent(new CustomEvent('select', { detail: { value: 'map' } }));
        po.byId('menu').dispatchEvent(new CustomEvent('select', { detail: { value: 'result' } }));
        expect(opened.mock.calls[0][0].detail.chainId).toBe('chain-failed');
        expect(result.mock.calls[0][0].detail.resultId).toBe(seq.steps[0].id);
    });

    it('forwards a replay link from a step', async () => {
        const seq = failedSequence();
        seq.steps[2].requeueStatus = 'Requeued';
        seq.steps[2].replayResultId = 'a0X000000000002AAA';
        seq.steps[2].replayChainId = 'chain-replay';
        const po = await mount(seq);
        const handler = jest.fn();
        po.el.addEventListener('openreplay', handler);
        po.steps[2].dispatchEvent(
            new CustomEvent('openreplay', {
                detail: { resultId: 'a0X000000000002AAA', chainId: 'chain-replay' }
            })
        );
        expect(handler.mock.calls[0][0].detail.chainId).toBe('chain-replay');
    });

    it('renders the menu alone when there is nothing to requeue', async () => {
        const po = await mount(completedSequence());
        expect(po.el.shadowRoot.querySelector('lightning-button-group')).toBeNull();
        expect(po.byId('menu')).not.toBeNull();
    });

    it('labels a replay with the result it was requeued from', async () => {
        const replay = runningSequence();
        replay.steps[0].requeuedFrom = 'a00000000000001AAA';
        replay.steps[0].requeuedFromName = 'AR-00231';
        const po = await mount(replay);
        expect(po.byId('replay-of').textContent).toContain('AR-00231');
    });
});
