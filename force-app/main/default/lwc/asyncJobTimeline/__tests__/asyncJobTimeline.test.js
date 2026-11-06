import { createElement } from 'lwc';
import AsyncJobTimeline from 'c/asyncJobTimeline';
import load from '@salesforce/apex/AsyncJobTimelineController.load';
import poll from '@salesforce/apex/AsyncJobTimelineController.poll';
import requeue from '@salesforce/apex/AsyncJobTimelineController.requeue';
import { POLL, VERSION } from 'c/asyncJobTimelineModel';
import AsyncChainMap from 'c/asyncChainMap';
import {
    page,
    failedSequence,
    runningSequence,
    completedSequence,
    flushPromises,
    step,
    sequence
} from './data/fixtures';

jest.mock('lightning/confirm', () => ({
    __esModule: true,
    default: { open: jest.fn().mockResolvedValue(true) }
}));
import LightningConfirm from 'lightning/confirm';

const mockNavigate = jest.fn();
jest.mock(
    'lightning/navigation',
    () => {
        const Navigate = Symbol('Navigate');
        const GenerateUrl = Symbol('GenerateUrl');
        const NavigationMixin = Base =>
            class extends Base {
                [Navigate](pageReference) {
                    mockNavigate(pageReference);
                }
                [GenerateUrl]() {
                    return Promise.resolve('#');
                }
            };
        NavigationMixin.Navigate = Navigate;
        NavigationMixin.GenerateUrl = GenerateUrl;
        return { NavigationMixin, CurrentPageReference: jest.fn() };
    },
    { virtual: true }
);
jest.mock('@salesforce/apex/AsyncJobTimelineController.load', () => ({ default: jest.fn() }), {
    virtual: true
});
jest.mock('@salesforce/apex/AsyncJobTimelineController.poll', () => ({ default: jest.fn() }), {
    virtual: true
});
jest.mock('@salesforce/apex/AsyncJobTimelineController.requeue', () => ({ default: jest.fn() }), {
    virtual: true
});

class TimelinePO {
    constructor(el) {
        this.el = el;
    }
    get root() {
        return this.el.shadowRoot;
    }
    byId(id) {
        return this.root.querySelector(`[data-id="${id}"]`);
    }
    get sequences() {
        return [...this.root.querySelectorAll('c-async-job-sequence')];
    }
    get liveText() {
        return this.byId('live')?.textContent.trim();
    }
    chip(name) {
        return this.byId('chip-' + name);
    }
}

const mount = async (props = {}) => {
    const el = createElement('c-async-job-timeline', { is: AsyncJobTimeline });
    el.recordId = '001000000000001AAA';
    Object.assign(el, props);
    document.body.appendChild(el);
    await flushPromises();
    return new TimelinePO(el);
};

describe('c-async-job-timeline', () => {
    beforeEach(() => {
        jest.useFakeTimers({ doNotFake: ['nextTick', 'setImmediate', 'queueMicrotask'] });
        poll.mockResolvedValue({ fingerprint: 'fp-1', apexJobStatusById: {} });
    });

    afterEach(() => {
        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
        jest.clearAllMocks();
        jest.useRealTimers();
    });

    it('shows a loading skeleton until the page arrives', () => {
        load.mockReturnValue(new Promise(() => {}));
        const el = createElement('c-async-job-timeline', { is: AsyncJobTimeline });
        el.recordId = '001000000000001AAA';
        document.body.appendChild(el);
        expect(el.shadowRoot.querySelector('[data-id="loading"]')).not.toBeNull();
    });

    it('renders one sequence card per chain, prefetching a block of chains for the range', async () => {
        load.mockResolvedValue(page([failedSequence(), completedSequence()]));
        const po = await mount({ daysBack: 3, chainsPerPage: 5 });
        expect(po.sequences).toHaveLength(2);
        expect(load).toHaveBeenCalledWith({
            request: {
                recordId: '001000000000001AAA',
                daysBack: 3,
                chainLimit: 50,
                chainOffset: 0,
                statusFilter: 'all',
                keepChainIds: []
            }
        });
        expect(po.byId('loading')).toBeNull();
    });

    it('expands only the first in-flight sequence by default', async () => {
        load.mockResolvedValue(page([failedSequence(), runningSequence(), completedSequence()]));
        const po = await mount();
        expect(po.sequences.map(card => card.defaultExpanded)).toEqual([false, true, false]);
    });

    describe('which chains open', () => {
        const queuedSequence = () =>
            sequence('chain-queued', [
                step({ customJobId: 'q1', status: 'ENQUEUED', apexJobStatus: 'Queued' })
            ]);
        const running = id => ({ ...runningSequence(), chainId: id });
        const openFlags = po => po.sequences.map(card => card.defaultExpanded);
        const toggle = async card => {
            card.shadowRoot.querySelector('[data-id="head"]').click();
            await flushPromises();
        };
        const pick = async (po, name) => {
            po.chip(name).click();
            await flushPromises();
        };

        it('opens nothing when nothing runs on the first page', async () => {
            load.mockResolvedValue(page([failedSequence(), completedSequence()]));
            const po = await mount();
            expect(openFlags(po)).toEqual([false, false]);
        });

        it('opens nothing for a chain that only waits in the queue', async () => {
            load.mockResolvedValue(page([queuedSequence(), completedSequence()]));
            const po = await mount();
            expect(openFlags(po)).toEqual([false, false]);
        });

        it('opens only the first running chain', async () => {
            load.mockResolvedValue(page([running('one'), running('two')]));
            const po = await mount();
            expect(openFlags(po)).toEqual([true, false]);
        });

        it('never opens by itself under a filter', async () => {
            load.mockResolvedValueOnce(page([completedSequence()]));
            const po = await mount();
            load.mockResolvedValue(page([running('one')]));
            await pick(po, 'inflight');
            expect(openFlags(po)).toEqual([false]);
        });

        it('never opens a running chain that is not on the first page', async () => {
            const finished = Array.from({ length: 7 }, (_, index) =>
                completedSequence(`done-${index}`)
            );
            load.mockResolvedValue(page([...finished, running('later')], { totalChainCount: 8 }));
            const po = await mount();
            po.byId('next').click();
            await flushPromises();
            expect(po.sequences.map(card => card.sequence.chainId)).toEqual(['later']);
            expect(openFlags(po)).toEqual([false]);
        });

        it('keeps a chain you closed closed after visiting a filter', async () => {
            load.mockResolvedValue(page([running('one'), completedSequence()]));
            const po = await mount();
            await toggle(po.sequences[0]);
            await pick(po, 'failed');
            await pick(po, 'all');
            expect(openFlags(po)).toEqual([false, false]);
            expect(po.sequences[0].shadowRoot.querySelector('[data-id="body"]')).toBeNull();
        });

        it('keeps a chain you opened open after visiting a filter', async () => {
            const done = completedSequence('kept');
            load.mockResolvedValue(page([done]));
            const po = await mount();
            await toggle(po.sequences[0]);
            load.mockResolvedValueOnce(page([]));
            await pick(po, 'failed');
            expect(po.sequences).toHaveLength(0);
            await pick(po, 'all');
            expect(po.sequences[0].shadowRoot.querySelector('[data-id="body"]')).not.toBeNull();
        });

        it('keeps a chain you opened open after paging away and back', async () => {
            const finished = Array.from({ length: 8 }, (_, index) =>
                completedSequence(`done-${index}`)
            );
            load.mockResolvedValue(page(finished, { totalChainCount: 8 }));
            const po = await mount();
            await toggle(po.sequences[1]);
            po.byId('next').click();
            await flushPromises();
            po.byId('prev').click();
            await flushPromises();
            expect(po.sequences[1].shadowRoot.querySelector('[data-id="body"]')).not.toBeNull();
        });

        it('does not open another running chain when you close the open one', async () => {
            load.mockResolvedValue(page([running('one'), running('two')]));
            const po = await mount();
            await toggle(po.sequences[0]);
            po.byId('refresh').click();
            await flushPromises();
            expect(openFlags(po)).toEqual([false, false]);
        });

        it('opens a chain that starts later when nothing else is open', async () => {
            load.mockResolvedValueOnce(page([completedSequence()]));
            const po = await mount();
            load.mockResolvedValue(page([running('late'), completedSequence()]));
            po.byId('refresh').click();
            await flushPromises();
            expect(openFlags(po)).toEqual([true, false]);
        });
    });

    it('explains a missing permission set instead of a raw error', async () => {
        load.mockRejectedValue({
            body: {
                message:
                    'You cannot read async job results. Ask an admin for the Async Result Access permission set.'
            }
        });
        const po = await mount();
        expect(po.byId('error').textContent).toContain('Async Result Access');
        expect(po.sequences).toHaveLength(0);
    });

    it('shows an empty state with the count of older sequences and the list link', async () => {
        load.mockResolvedValue(page([], { olderChainCount: 3 }));
        const po = await mount();
        expect(po.byId('empty').textContent).toContain('last 7 days');
        expect(po.byId('older-count').textContent).toContain('3 older');
        expect(po.byId('view-all')).not.toBeNull();
        expect(po.byId('view-all-foot')).toBeNull();
    });

    it('lays the legend over the list and closes it on Escape, outside click or its X', async () => {
        load.mockResolvedValue(page());
        const po = await mount();
        const heightBefore = po.byId('scroller').getAttribute('style');
        po.byId('help').click();
        await flushPromises();
        expect(po.byId('legend').getAttribute('role')).toBe('dialog');
        expect(po.byId('scroller').getAttribute('style')).toBe(heightBefore);
        expect(po.byId('legend').parentElement).toBe(po.byId('scroller').parentElement);
        po.byId('legend').dispatchEvent(new MouseEvent('click', { bubbles: true, composed: true }));
        await flushPromises();
        expect(po.byId('legend')).not.toBeNull();
        document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
        await flushPromises();
        expect(po.byId('legend')).toBeNull();
        po.byId('help').click();
        await flushPromises();
        po.byId('scroller').click();
        await flushPromises();
        expect(po.byId('legend')).toBeNull();
        po.byId('help').click();
        await flushPromises();
        po.byId('legend-close').click();
        await flushPromises();
        expect(po.byId('legend')).toBeNull();
    });

    it('signs the footer with the version and links to the docs and the maker', async () => {
        load.mockResolvedValue(page());
        const po = await mount();
        const library = po.byId('brand');
        const maker = po.byId('brand-maker');
        expect(library.textContent.replace(/\s+/g, '')).toBe(`AsyncLibv${VERSION}`);
        expect(maker.textContent.replace(/\s+/g, '')).toBe('byBeyondTheCloud');
        expect(library.querySelector('a').href).toBe('https://async.beyondthecloud.dev/');
        expect(maker.querySelector('a').href).toBe('https://beyondthecloud.dev/');
        expect(po.root.querySelector('.logo img').getAttribute('src')).toContain('AsyncLibLogo');
    });

    it('counts chips over the whole range and filters on the server', async () => {
        load.mockResolvedValueOnce(
            page([failedSequence(), runningSequence(), completedSequence()], {
                counts: { all: 12, inflight: 2, failed: 4, completed: 6 }
            })
        );
        load.mockResolvedValueOnce(page([failedSequence()], { totalChainCount: 4 }));
        const po = await mount();
        expect(po.chip('all').textContent).toContain('12');
        expect(po.chip('inflight').textContent).toContain('2');
        expect(po.chip('failed').textContent).toContain('4');
        expect(po.chip('completed').textContent).toContain('6');
        po.chip('failed').click();
        await flushPromises();
        expect(load).toHaveBeenLastCalledWith({
            request: expect.objectContaining({ statusFilter: 'failed', chainOffset: 0 })
        });
        expect(po.sequences).toHaveLength(1);
        expect(po.sequences[0].sequence.chainId).toBe('chain-failed');
    });

    describe('In flight chip', () => {
        const withCounts = (inflight, sequences = [completedSequence('a')]) =>
            page(sequences, {
                counts: { all: 3, inflight, failed: 0, completed: 3 - inflight },
                totalChainCount: sequences.length
            });
        const dotOf = po => po.chip('inflight').querySelector('[data-id="chip-dot"]');

        it('turns live with a pulsing dot while something runs', async () => {
            load.mockResolvedValue(withCounts(2, [runningSequence()]));
            const po = await mount();
            expect(po.chip('inflight').classList.contains('chip-live')).toBe(true);
            expect(dotOf(po).classList.contains('is-paused')).toBe(false);
        });

        it('goes plain when nothing runs', async () => {
            load.mockResolvedValue(withCounts(0));
            const po = await mount();
            expect(po.chip('inflight').classList.contains('chip-live')).toBe(false);
            expect(dotOf(po)).toBeNull();
        });

        it('stops pulsing when live refresh is off', async () => {
            load.mockResolvedValue(withCounts(2, [runningSequence()]));
            const po = await mount({ liveRefreshOff: true });
            expect(dotOf(po).classList.contains('is-paused')).toBe(true);
        });

        it('asks to keep the chains it showed while the filter stays on, and forgets them after', async () => {
            load.mockResolvedValue(withCounts(1, [runningSequence()]));
            const po = await mount();
            const watchedId = runningSequence().chainId;
            po.chip('inflight').click();
            await flushPromises();
            expect(load).toHaveBeenLastCalledWith({
                request: expect.objectContaining({
                    statusFilter: 'inflight',
                    keepChainIds: [watchedId]
                })
            });
            po.chip('all').click();
            await flushPromises();
            expect(load).toHaveBeenLastCalledWith({
                request: expect.objectContaining({ statusFilter: 'all', keepChainIds: [] })
            });
        });
    });

    describe('compact layout controls', () => {
        it('offers a shorter range menu that changes the same range', async () => {
            load.mockResolvedValue(page([completedSequence()]));
            const po = await mount();
            const compact = po.byId('range-compact');
            expect(compact.label).toBe('7 days');
            compact.dispatchEvent(new CustomEvent('select', { detail: { value: '30' } }));
            await flushPromises();
            expect(load).toHaveBeenLastCalledWith({
                request: expect.objectContaining({ daysBack: 30 })
            });
        });

        it('offers view all results as an icon', async () => {
            load.mockResolvedValue(page([completedSequence()]));
            const po = await mount();
            const compact = po.byId('view-all-compact');
            expect(compact.title).toBe('View all results');
            compact.click();
            expect(mockNavigate).toHaveBeenCalled();
        });
    });

    describe('footer', () => {
        it('puts the library on the left and the maker on the right', async () => {
            load.mockResolvedValue(page([completedSequence()]));
            const po = await mount();
            const foot = po.root.querySelector('.foot');
            const parts = [...foot.children];
            expect(parts[0].textContent).toContain(`Async Lib`);
            expect(parts[0].textContent).toContain(`v${VERSION}`);
            expect(parts[parts.length - 1].textContent).toContain('Beyond The Cloud');
            expect(parts[parts.length - 1].textContent).not.toContain('Async Lib');
        });

        it('keeps the older count out of the three columns', async () => {
            load.mockResolvedValue(page([completedSequence()], { olderChainCount: 3 }));
            const po = await mount();
            expect(po.byId('older-count').closest('.foot-older')).not.toBeNull();
        });
    });

    describe('switching lists', () => {
        const LINE_DELAY_MS = 300;
        const deferred = () => {
            let resolve;
            let reject;
            const promise = new Promise((res, rej) => {
                resolve = res;
                reject = rej;
            });
            return { promise, resolve, reject };
        };
        const ids = po => po.sequences.map(card => card.sequence.chainId);
        const everything = () =>
            page([failedSequence(), completedSequence('done')], {
                counts: { all: 2, inflight: 0, failed: 1, completed: 1 },
                totalChainCount: 2
            });
        const tooManyToHold = () =>
            page([failedSequence(), completedSequence('done')], {
                counts: { all: 80, inflight: 0, failed: 1, completed: 79 },
                totalChainCount: 80,
                hasMore: true
            });
        const openFilter = async (po, name) => {
            po.chip(name).click();
            await flushPromises();
        };
        const line = po => po.byId('load-line');
        const passLineDelay = async () => {
            jest.advanceTimersByTime(LINE_DELAY_MS);
            await flushPromises();
        };

        it('filters what it holds at once, before the server answers', async () => {
            load.mockResolvedValueOnce(everything());
            const po = await mount();
            const answer = deferred();
            load.mockReturnValueOnce(answer.promise);
            await openFilter(po, 'failed');
            expect(ids(po)).toEqual(['chain-failed']);
            answer.resolve(page([failedSequence()], { counts: everything().counts }));
            await flushPromises();
        });

        it('does not bring a finished chain back to life when switching lists', async () => {
            const watched = { ...runningSequence(), chainId: 'watched' };
            const finished = { ...completedSequence('done'), chainId: 'watched' };
            load.mockResolvedValueOnce(
                page([watched], {
                    counts: { all: 1, inflight: 1, failed: 0, completed: 0 },
                    totalChainCount: 1
                })
            );
            const po = await mount();
            load.mockResolvedValueOnce(
                page([finished], {
                    counts: { all: 1, inflight: 0, failed: 0, completed: 1 },
                    totalChainCount: 1
                })
            );
            await openFilter(po, 'inflight');
            const answer = deferred();
            load.mockReturnValueOnce(answer.promise);
            await openFilter(po, 'all');
            expect(po.chip('inflight').textContent).toContain('0');
            expect(po.chip('inflight').classList.contains('chip-live')).toBe(false);
            answer.resolve(page([finished], { totalChainCount: 1 }));
            await flushPromises();
        });

        it('shows a chain first seen under another filter at once on the others', async () => {
            const arrived = { ...runningSequence(), chainId: 'arrived' };
            load.mockResolvedValueOnce(
                page([completedSequence('done')], {
                    counts: { all: 1, inflight: 0, failed: 0, completed: 1 },
                    totalChainCount: 1
                })
            );
            const po = await mount();
            load.mockResolvedValueOnce(
                page([arrived], {
                    counts: { all: 2, inflight: 1, failed: 0, completed: 1 },
                    totalChainCount: 1
                })
            );
            await openFilter(po, 'inflight');
            const answer = deferred();
            load.mockReturnValueOnce(answer.promise);
            await openFilter(po, 'all');
            expect(ids(po)).toEqual(['arrived', 'done']);
            answer.resolve(page([arrived, completedSequence('done')], { totalChainCount: 2 }));
            await flushPromises();
        });

        it('updates the view in place when the server knows more', async () => {
            load.mockResolvedValueOnce(everything());
            const po = await mount();
            const answer = deferred();
            load.mockReturnValueOnce(answer.promise);
            await openFilter(po, 'failed');
            const shown = po.sequences[0];
            answer.resolve(
                page([{ ...failedSequence(), chainId: 'late-failure' }, failedSequence()], {
                    counts: { all: 3, inflight: 0, failed: 2, completed: 1 },
                    totalChainCount: 2
                })
            );
            await flushPromises();
            expect(ids(po)).toEqual(['late-failure', 'chain-failed']);
            expect(po.sequences[1]).toBe(shown);
            expect(po.chip('failed').textContent).toContain('2');
        });

        it('shows no line while the list is already right', async () => {
            load.mockResolvedValueOnce(everything());
            const po = await mount();
            const answer = deferred();
            load.mockReturnValueOnce(answer.promise);
            await openFilter(po, 'failed');
            await passLineDelay();
            expect(line(po)).toBeNull();
            answer.resolve(page([failedSequence()]));
            await flushPromises();
        });

        it('does not flash a chain when the refresh changes nothing', async () => {
            load.mockResolvedValue(everything());
            const po = await mount();
            await openFilter(po, 'failed');
            await openFilter(po, 'all');
            po.sequences.forEach(card => {
                expect(card.highlight).toEqual({ added: [], changed: [] });
            });
        });

        it('keeps the list and says so when the refresh fails', async () => {
            load.mockResolvedValueOnce(everything());
            const po = await mount();
            load.mockRejectedValueOnce(new Error('503'));
            await openFilter(po, 'failed');
            expect(po.byId('error')).toBeNull();
            expect(ids(po)).toEqual(['chain-failed']);
            expect(po.liveText).toContain('Could not refresh');
        });

        describe('with more chains than it holds', () => {
            it('keeps the rows until the answer and shows the line only after the delay', async () => {
                load.mockResolvedValueOnce(tooManyToHold());
                const po = await mount();
                const answer = deferred();
                load.mockReturnValueOnce(answer.promise);
                await openFilter(po, 'failed');
                expect(ids(po)).toEqual(['chain-failed', 'done']);
                expect(line(po)).toBeNull();
                await passLineDelay();
                expect(line(po)).not.toBeNull();
                answer.resolve(page([failedSequence()], { totalChainCount: 1 }));
                await flushPromises();
                expect(ids(po)).toEqual(['chain-failed']);
                expect(line(po)).toBeNull();
            });

            it('never shows the line for a quick answer', async () => {
                load.mockResolvedValue(tooManyToHold());
                const po = await mount();
                await openFilter(po, 'failed');
                await passLineDelay();
                expect(line(po)).toBeNull();
            });

            it('holds the rows and shows the line when the pager crosses into the next block', async () => {
                const chains = Array.from({ length: 50 }, (_, index) =>
                    completedSequence(`c${index}`)
                );
                load.mockResolvedValueOnce(page(chains, { totalChainCount: 80, hasMore: true }));
                const po = await mount();
                const lastPageOfBlock = 7;
                for (let i = 0; i < lastPageOfBlock; i++) po.byId('next').click();
                await flushPromises();
                const before = ids(po);
                const answer = deferred();
                load.mockReturnValueOnce(answer.promise);
                po.byId('next').click();
                await flushPromises();
                expect(ids(po)).toEqual(before);
                await passLineDelay();
                expect(line(po)).not.toBeNull();
                answer.resolve(
                    page([completedSequence('c50')], { totalChainCount: 80, hasMore: false })
                );
                await flushPromises();
                expect(line(po)).toBeNull();
                expect(ids(po)).not.toEqual(before);
            });

            it('shows the error when there is no right list to keep', async () => {
                load.mockResolvedValueOnce(tooManyToHold());
                const po = await mount();
                load.mockRejectedValueOnce(new Error('503'));
                await openFilter(po, 'failed');
                expect(po.byId('error')).not.toBeNull();
                expect(line(po)).toBeNull();
            });
        });

        it('never shows the line for a background refresh', async () => {
            load.mockResolvedValueOnce(tooManyToHold());
            const po = await mount();
            const answer = deferred();
            load.mockReturnValueOnce(answer.promise);
            po.byId('refresh').click();
            await flushPromises();
            await passLineDelay();
            expect(line(po)).toBeNull();
            answer.resolve(tooManyToHold());
            await flushPromises();
        });
    });

    it('pages in memory through the prefetched block', async () => {
        load.mockResolvedValue(
            page([completedSequence('a'), completedSequence('b'), completedSequence('c')], {
                totalChainCount: 3
            })
        );
        const po = await mount({ chainsPerPage: 1 });
        expect(po.sequences).toHaveLength(1);
        expect(po.byId('pager').textContent).toContain('1-1 of 3');
        expect(po.byId('prev').disabled).toBe(true);
        po.byId('next').click();
        await flushPromises();
        expect(load).toHaveBeenCalledTimes(1);
        expect(po.sequences[0].sequence.chainId).toBe('b');
        expect(po.byId('pager').textContent).toContain('2-2 of 3');
        expect(po.byId('prev').disabled).toBe(false);
        po.byId('next').click();
        await flushPromises();
        expect(po.byId('next').disabled).toBe(true);
    });

    it('fetches the next block when paging beyond the prefetched chains', async () => {
        const block = Array.from({ length: 50 }, (_, i) => completedSequence('c' + i));
        load.mockResolvedValueOnce(page(block, { hasMore: true, totalChainCount: 60 }));
        load.mockResolvedValueOnce(
            page([completedSequence('c50')], { hasMore: false, totalChainCount: 60 })
        );
        const po = await mount({ chainsPerPage: 50 });
        po.byId('next').click();
        await flushPromises();
        expect(load).toHaveBeenLastCalledWith({
            request: expect.objectContaining({ chainOffset: 50 })
        });
        expect(po.sequences[0].sequence.chainId).toBe('c50');
    });

    it('does not drop a pager click while a background refresh runs', async () => {
        load.mockResolvedValue(
            page([completedSequence('a'), completedSequence('b'), completedSequence('c')], {
                totalChainCount: 3
            })
        );
        const po = await mount({ chainsPerPage: 1 });
        po.byId('last').click();
        await flushPromises();
        expect(po.byId('pager').textContent).toContain('3-3 of 3');
        let finishRefresh;
        load.mockReturnValueOnce(
            new Promise(resolve => {
                finishRefresh = resolve;
            })
        );
        po.byId('refresh').click();
        await flushPromises();
        po.byId('first').click();
        await flushPromises();
        expect(po.byId('pager').textContent).toContain('1-1 of 3');
        finishRefresh(
            page([completedSequence('a'), completedSequence('b'), completedSequence('c')], {
                totalChainCount: 3
            })
        );
        await flushPromises();
        expect(po.sequences[0].sequence.chainId).toBe('a');
    });

    it('ignores the response of an older request that lands after a newer one', async () => {
        const block = Array.from({ length: 50 }, (_, i) => completedSequence('c' + i));
        load.mockResolvedValueOnce(page(block, { hasMore: true, totalChainCount: 60 }));
        const po = await mount({ chainsPerPage: 50 });
        let finishOlder;
        let finishNewer;
        load.mockReturnValueOnce(
            new Promise(resolve => {
                finishOlder = resolve;
            })
        );
        load.mockReturnValueOnce(
            new Promise(resolve => {
                finishNewer = resolve;
            })
        );
        po.byId('refresh').click();
        await flushPromises();
        po.byId('next').click();
        await flushPromises();
        finishNewer(page([completedSequence('c50')], { totalChainCount: 60 }));
        await flushPromises();
        finishOlder(page(block, { hasMore: true, totalChainCount: 60 }));
        await flushPromises();
        expect(po.sequences[0].sequence.chainId).toBe('c50');
    });

    it('opens a replay in place when it is loaded, else navigates to its result', async () => {
        const replay = completedSequence('chain-replay');
        load.mockResolvedValue(page([failedSequence(), replay]));
        const po = await mount();
        po.sequences[1].expand = jest.fn();
        po.sequences[1].scrollTo = jest.fn();
        po.sequences[0].dispatchEvent(
            new CustomEvent('openreplay', {
                detail: { resultId: 'a0X000000000002AAA', chainId: 'chain-replay' }
            })
        );
        await flushPromises();
        expect(po.sequences[1].expand).toHaveBeenCalled();
        expect(mockNavigate).not.toHaveBeenCalled();
        po.sequences[0].dispatchEvent(
            new CustomEvent('openreplay', {
                detail: { resultId: 'a0X000000000003AAA', chainId: 'chain-elsewhere' }
            })
        );
        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__recordPage',
            attributes: { recordId: 'a0X000000000003AAA', actionName: 'view' }
        });
    });

    it('offers a range menu, defaults to 7 days and reloads from the first page on change', async () => {
        load.mockResolvedValue(page([completedSequence()]));
        const po = await mount({ daysBack: undefined });
        expect(load).toHaveBeenLastCalledWith({
            request: expect.objectContaining({ daysBack: 7 })
        });
        expect(po.byId('range').label).toBe('Last 7 days');
        po.byId('range').dispatchEvent(new CustomEvent('select', { detail: { value: '0' } }));
        await flushPromises();
        expect(load).toHaveBeenLastCalledWith({
            request: expect.objectContaining({ daysBack: 0, chainOffset: 0 })
        });
        expect(po.byId('range').label).toBe('All time');
    });

    it('holds a fixed height and fits the page size to it', async () => {
        const many = Array.from({ length: 12 }, (_, i) => completedSequence('c' + i));
        load.mockResolvedValue(page(many, { totalChainCount: 12 }));
        const po = await mount({ maxHeight: 400 });
        expect(po.byId('scroller').style.height).toBe('400px');
        expect(po.sequences).toHaveLength(4);
        expect(po.byId('pager').textContent).toContain('1-4 of 12');
        const explicit = await mount({ maxHeight: 400, chainsPerPage: 3 });
        expect(explicit.sequences).toHaveLength(3);
        const grow = await mount({ maxHeight: 0 });
        expect(grow.byId('scroller').style.height).toBe('');
    });

    it('scrolls the list by the amount a toggled header moved, in the same pass', async () => {
        const many = Array.from({ length: 12 }, (_, i) => completedSequence('c' + i));
        load.mockResolvedValue(page(many, { totalChainCount: 12 }));
        const po = await mount({ maxHeight: 400 });
        const scroller = po.byId('scroller');
        Object.defineProperties(scroller, {
            scrollHeight: { value: 1000, configurable: true },
            clientHeight: { value: 400, configurable: true },
            scrollTop: { value: 300, writable: true, configurable: true }
        });
        const toggle = (card, delta, open) =>
            card.dispatchEvent(
                new CustomEvent('sequencetoggle', { detail: { open, delta }, bubbles: false })
            );
        toggle(po.sequences[1], -200, false);
        expect(scroller.scrollTop).toBe(100);
        expect(po.byId('filler')).toBeNull();

        toggle(po.sequences[1], 700, true);
        await flushPromises();
        expect(po.byId('filler').style.height).toBe('200px');
        expect(scroller.scrollTop).toBe(800);

        Object.defineProperty(scroller, 'scrollHeight', { value: 1200, configurable: true });
        scroller.scrollTop = 500;
        scroller.dispatchEvent(new CustomEvent('scroll'));
        await flushPromises();
        expect(po.byId('filler')).toBeNull();
    });

    it('keeps a filler that is still in view', async () => {
        const many = Array.from({ length: 12 }, (_, i) => completedSequence('c' + i));
        load.mockResolvedValue(page(many, { totalChainCount: 12 }));
        const po = await mount({ maxHeight: 400 });
        const scroller = po.byId('scroller');
        Object.defineProperties(scroller, {
            scrollHeight: { value: 1000, configurable: true },
            clientHeight: { value: 400, configurable: true },
            scrollTop: { value: 600, writable: true, configurable: true }
        });
        po.sequences[1].dispatchEvent(
            new CustomEvent('sequencetoggle', { detail: { open: true, delta: 100 } })
        );
        await flushPromises();
        expect(po.byId('filler').style.height).toBe('100px');
        Object.defineProperty(scroller, 'scrollHeight', { value: 1100, configurable: true });
        scroller.scrollTop = 650;
        scroller.dispatchEvent(new CustomEvent('scroll'));
        await flushPromises();
        expect(po.byId('filler').style.height).toBe('100px');
    });

    it('keeps the first in-flight chain open after it settles and only flags newcomers', async () => {
        const running = runningSequence();
        const settled = runningSequence();
        settled.steps.forEach(row => {
            row.status = 'COMPLETED';
            row.apexJobStatus = undefined;
        });
        const newcomer = runningSequence();
        newcomer.chainId = 'chain-new';
        load.mockResolvedValueOnce(page([running])).mockResolvedValueOnce(
            page([newcomer, settled], { fingerprint: 'fp-2' })
        );
        poll.mockResolvedValueOnce({ fingerprint: 'fp-2', apexJobStatusById: {} });
        const po = await mount();
        expect(po.sequences[0].defaultExpanded).toBe(true);
        jest.advanceTimersByTime(POLL.running);
        await flushPromises();
        await flushPromises();
        expect(po.sequences.map(card => card.sequence.chainId)).toEqual([
            'chain-new',
            'chain-running'
        ]);
        expect(po.sequences[1].defaultExpanded).toBe(true);
        expect(po.sequences[0].defaultExpanded).toBe(false);
        expect(po.sequences[0].isNew).toBe(true);
        expect(po.liveText).toContain('1 new sequence running');
    });

    it('follows a newcomer when follow new runs is on', async () => {
        const running = runningSequence();
        const newcomer = runningSequence();
        newcomer.chainId = 'chain-new';
        load.mockResolvedValueOnce(page([running])).mockResolvedValueOnce(
            page([newcomer, running], { fingerprint: 'fp-2' })
        );
        poll.mockResolvedValueOnce({ fingerprint: 'fp-2', apexJobStatusById: {} });
        const po = await mount({ followNewRuns: true });
        expect(po.byId('follow').checked).toBe(true);
        expect(po.byId('follow').type).toBe('toggle');
        jest.advanceTimersByTime(POLL.running);
        await flushPromises();
        await flushPromises();
        expect(po.sequences[0].defaultExpanded).toBe(true);
        expect(po.sequences[1].defaultExpanded).toBe(false);
        expect(po.sequences[0].isNew).toBe(false);
        po.byId('follow').dispatchEvent(new CustomEvent('change', { detail: { checked: false } }));
        await flushPromises();
        expect(po.byId('follow').checked).toBe(false);
        po.byId('follow-label').click();
        await flushPromises();
        expect(po.byId('follow').checked).toBe(true);
    });

    it('refreshes in place from the button without a spinner', async () => {
        load.mockResolvedValueOnce(page([completedSequence()]));
        load.mockReturnValueOnce(new Promise(() => {}));
        const po = await mount();
        po.byId('refresh').click();
        await flushPromises();
        expect(po.byId('loading')).toBeNull();
        expect(po.sequences).toHaveLength(1);
        expect(po.liveText).toContain('Refreshing');
        expect(load).toHaveBeenCalledTimes(2);
    });

    it('flags a stale idle card after ten minutes without a check', async () => {
        load.mockResolvedValue(page([completedSequence()]));
        const po = await mount();
        expect(po.byId('refresh').variant).not.toBe('brand');
        jest.advanceTimersByTime(POLL.staleMinutes * 60 * 1000 + 31000);
        await flushPromises();
        expect(po.byId('refresh').variant).toBe('brand');
        expect(po.liveText).toContain('Last checked');
        expect(po.liveText).toContain('min ago');
    });

    it('checks right away when the tab becomes visible again', async () => {
        load.mockResolvedValue(page([runningSequence()]));
        await mount();
        Object.defineProperty(document, 'visibilityState', { value: 'hidden', configurable: true });
        document.dispatchEvent(new CustomEvent('visibilitychange'));
        await flushPromises();
        Object.defineProperty(document, 'visibilityState', {
            value: 'visible',
            configurable: true
        });
        document.dispatchEvent(new CustomEvent('visibilitychange'));
        await flushPromises();
        expect(poll).toHaveBeenCalledTimes(1);
    });

    it('polls only while a chain is in flight and reloads when the fingerprint moves', async () => {
        load.mockResolvedValue(page([runningSequence()]));
        const po = await mount();
        expect(po.liveText).toBe('Live');
        expect(po.byId('live').getAttribute('title')).toContain('every 3 s');
        expect(po.sequences[0].pageRecordId).toBe('001000000000001AAA');
        poll.mockResolvedValueOnce({ fingerprint: 'fp-2', apexJobStatusById: {} });
        jest.advanceTimersByTime(POLL.running);
        await flushPromises();
        expect(poll).toHaveBeenCalledWith({
            recordId: '001000000000001AAA',
            chainIds: ['chain-running']
        });
        expect(load).toHaveBeenCalledTimes(2);
    });

    it('does not poll when nothing is in flight', async () => {
        load.mockResolvedValue(page([failedSequence(), completedSequence()]));
        const po = await mount();
        jest.advanceTimersByTime(POLL.queued * 3);
        await flushPromises();
        expect(poll).not.toHaveBeenCalled();
        expect(po.liveText).toBe('Idle');
        expect(po.byId('live').getAttribute('title')).toContain('Nothing in flight');
    });

    it('names the clock time of the next check while every step waits for its retry', async () => {
        const retrying = runningSequence();
        retrying.steps[1].apexJobStatus = null;
        retrying.steps[1].retryAttempts = 1;
        retrying.steps[1].nextAttemptAt = new Date(Date.now() + 4 * 60000).toISOString();
        retrying.steps = retrying.steps.slice(0, 2);
        load.mockResolvedValue(page([retrying]));
        const po = await mount();
        expect(po.liveText).toContain('Live · next check');
        const at = po.byId('live').querySelector('lightning-formatted-date-time');
        expect(Date.parse(at.value)).toBeGreaterThan(Date.now() + 3 * 60000);
    });

    it('pauses while the tab is hidden and hard-stops after the polling budget', async () => {
        load.mockResolvedValue(page([runningSequence()]));
        const po = await mount();
        Object.defineProperty(document, 'visibilityState', { value: 'hidden', configurable: true });
        document.dispatchEvent(new CustomEvent('visibilitychange'));
        await flushPromises();
        expect(po.liveText).toContain('Paused');
        Object.defineProperty(document, 'visibilityState', {
            value: 'visible',
            configurable: true
        });
        document.dispatchEvent(new CustomEvent('visibilitychange'));
        await flushPromises();
        jest.advanceTimersByTime(POLL.maxMinutes * 60 * 1000 + POLL.running);
        await flushPromises();
        expect(po.liveText).toContain('Paused');
        expect(po.byId('refresh')).not.toBeNull();
    });

    it('keeps polling after one failed poll and clears the error on the next success', async () => {
        load.mockResolvedValue(page([runningSequence()]));
        const po = await mount();
        poll.mockRejectedValueOnce(new Error('503'));
        jest.advanceTimersByTime(POLL.running);
        await flushPromises();
        expect(po.byId('error').textContent).toContain('503');
        poll.mockResolvedValueOnce({ fingerprint: 'fp-1', apexJobStatusById: {} });
        jest.advanceTimersByTime(POLL.running);
        await flushPromises();
        expect(poll).toHaveBeenCalledTimes(2);
        expect(po.byId('error')).toBeNull();
        expect(po.liveText).toContain('Live');
    });

    it('stops live refresh after three failed polls in a row', async () => {
        load.mockResolvedValue(page([runningSequence()]));
        const po = await mount();
        poll.mockRejectedValue(new Error('503'));
        for (let i = 0; i < 4; i++) {
            jest.advanceTimersByTime(POLL.running);
            // eslint-disable-next-line no-await-in-loop
            await flushPromises();
        }
        expect(poll).toHaveBeenCalledTimes(3);
        expect(po.liveText).toContain('Paused');
        expect(po.byId('refresh')).not.toBeNull();
    });

    it('honours the live refresh switch', async () => {
        load.mockResolvedValue(page([runningSequence()]));
        const po = await mount({ liveRefreshOff: true });
        jest.advanceTimersByTime(POLL.running * 2);
        await flushPromises();
        expect(poll).not.toHaveBeenCalled();
        expect(po.byId('live')).toBeNull();
    });

    it('marks steps that appeared or changed since the previous load and announces them', async () => {
        const before = runningSequence();
        const after = runningSequence();
        after.steps[1].apexJobStatus = undefined;
        after.steps[1].status = 'COMPLETED';
        after.steps.splice(
            2,
            0,
            step({
                chainSequence: 3,
                customJobId: 'new-1',
                jobName: 'Calculate tax',
                status: 'ENQUEUED',
                addedByCustomJobId: 'r2'
            })
        );
        load.mockResolvedValueOnce(page([before])).mockResolvedValueOnce(
            page([after], { fingerprint: 'fp-2' })
        );
        poll.mockResolvedValueOnce({ fingerprint: 'fp-2', apexJobStatusById: {} });
        const po = await mount();
        jest.advanceTimersByTime(POLL.running);
        await flushPromises();
        await flushPromises();
        const highlight = po.sequences[0].highlight;
        expect(highlight.added).toEqual(['new-1']);
        expect(highlight.changed).toEqual(['r2']);
        expect(po.byId('announcer').textContent).toContain('Calculate tax added');
        jest.advanceTimersByTime(10000);
        await flushPromises();
        expect(po.sequences[0].highlight.added).toEqual([]);
    });

    it('hides requeue actions when the page says the viewer cannot requeue', async () => {
        load.mockResolvedValue(page([failedSequence()], { canRequeue: false }));
        const po = await mount();
        expect(po.sequences[0].canRequeue).toBe(false);
    });

    it('requeues on a child event, toasts the outcome and reloads', async () => {
        load.mockResolvedValue(page([failedSequence()]));
        requeue.mockResolvedValue({
            requeued: ['a1'],
            skipReasonByResultId: { a2: 'No payload was stored' },
            droppedDependencyByResultId: {},
            chainId: 'chain-new'
        });
        const po = await mount();
        const toasts = [];
        po.el.addEventListener('lightning__showtoast', event => toasts.push(event.detail));
        po.sequences[0].dispatchEvent(
            new CustomEvent('requeue', {
                detail: { resultIds: ['a1', 'a2'], label: '2 failed steps of Order' }
            })
        );
        await flushPromises();
        expect(LightningConfirm.open).toHaveBeenCalledWith(
            expect.objectContaining({ message: expect.stringContaining('2 failed steps of Order') })
        );
        expect(requeue).toHaveBeenCalledWith({ resultIds: ['a1', 'a2'] });
        expect(toasts[0].title).toContain('1 step requeued');
        expect(toasts[0].message).toContain('No payload was stored');
        expect(load).toHaveBeenCalledTimes(2);
        jest.advanceTimersByTime(POLL.afterRequeue);
        await flushPromises();
        expect(poll).toHaveBeenCalledTimes(1);
    });

    it('does nothing when the requeue confirmation is declined', async () => {
        load.mockResolvedValue(page([failedSequence()]));
        LightningConfirm.open.mockResolvedValueOnce(false);
        const po = await mount();
        po.sequences[0].dispatchEvent(
            new CustomEvent('requeue', { detail: { resultIds: ['a1'], label: 'x' } })
        );
        await flushPromises();
        expect(requeue).not.toHaveBeenCalled();
    });

    it('opens a result record from a sequence menu', async () => {
        load.mockResolvedValue(page([failedSequence()]));
        const po = await mount();
        po.sequences[0].dispatchEvent(
            new CustomEvent('openresult', { detail: { resultId: 'a0X000000000001AAA' } })
        );
        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__recordPage',
            attributes: { recordId: 'a0X000000000001AAA', actionName: 'view' }
        });
    });

    it('opens the chain map with the sequence and a label that survives a missing name', async () => {
        const unnamed = failedSequence();
        unnamed.name = null;
        load.mockResolvedValue(page([unnamed]));
        const po = await mount();
        po.sequences[0].dispatchEvent(
            new CustomEvent('openmap', { detail: { chainId: 'chain-failed' } })
        );
        await flushPromises();
        expect(AsyncChainMap.open).toHaveBeenCalledWith(
            expect.objectContaining({ sequence: unnamed, label: 'Chain map · Async jobs' })
        );
    });

    it('opens the By chain list view from the header button', async () => {
        load.mockResolvedValue(page([failedSequence()]));
        const po = await mount();
        po.byId('view-all').click();
        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__objectPage',
            attributes: { objectApiName: 'AsyncResult__c', actionName: 'list' },
            state: { filterName: 'ByChain' }
        });
    });

    it('toggles the legend from the help button', async () => {
        load.mockResolvedValue(page([completedSequence()]));
        const po = await mount();
        expect(po.byId('legend')).toBeNull();
        po.byId('help').click();
        await flushPromises();
        expect(po.byId('legend')).not.toBeNull();
    });

    it('renders a sequence with no steps without crashing', async () => {
        load.mockResolvedValue(page([sequence('empty-chain', [])]));
        const po = await mount();
        expect(po.sequences).toHaveLength(1);
    });
});
