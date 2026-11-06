import { createElement } from 'lwc';
import AsyncChainMap from 'c/asyncChainMap';
import { CAPS } from 'c/asyncJobTimelineModel';
import {
    failedSequence,
    longSequence,
    runningSequence,
    step,
    sequence,
    flushPromises
} from '../../asyncJobTimeline/__tests__/data/fixtures';

class MapPO {
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

const mount = async seq => {
    const el = createElement('c-async-chain-map', { is: AsyncChainMap });
    el.sequence = seq;
    document.body.appendChild(el);
    await flushPromises();
    return new MapPO(el);
};

describe('c-async-chain-map', () => {
    afterEach(() => {
        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
    });

    it('draws one node per step and one connector per dependency, coloured by outcome', async () => {
        const po = await mount(failedSequence());
        expect(po.all('[data-id="node"]')).toHaveLength(5);
        expect(po.all('[data-id="node"]')[2].classList.contains('node-bad')).toBe(true);
        expect(po.all('[data-id="node"] [data-id="node-name"]')[2].textContent).toBe(
            'Commission split'
        );
        expect(po.all('[data-id="arc"]')).toHaveLength(1);
        expect(po.all('[data-id="arc"]')[0].classList.contains('arc-unmet')).toBe(true);
        expect(po.all('[data-id="arc-label"]')[0].textContent).toContain('not met');
    });

    it('hangs finalizers under their parent and marks runtime inserts', async () => {
        const seq = sequence('c', [
            step({ chainSequence: 1, customJobId: 'c1', jobName: 'Create invoice' }),
            step({ chainSequence: 1, customJobId: 'f', parentCustomJobId: 'c1', jobName: 'Audit' }),
            step({
                chainSequence: 2,
                customJobId: 'x',
                jobName: 'Calculate tax',
                addedByCustomJobId: 'c1'
            })
        ]);
        const po = await mount(seq);
        expect(po.all('[data-id="node"]')).toHaveLength(2);
        expect(po.all('[data-id="fin"]')).toHaveLength(1);
        expect(po.all('[data-id="fin"]')[0].textContent).toContain('Audit');
        expect(po.all('[data-id="node"]')[1].classList.contains('node-added')).toBe(true);
        expect(po.all('[data-id="node"]')[1].textContent).toContain('added by Create invoice');
    });

    it('collapses long runs of completed nodes, expands one on click and selects the failed node', async () => {
        const po = await mount(longSequence(CAPS.mapBoxes + 20, 30));
        expect(po.all('[data-id="node"]').length).toBeLessThan(CAPS.mapBoxes);
        const collapsed = po.all('[data-id="node"].node-collapsed');
        expect(collapsed.length).toBeGreaterThan(0);
        expect(collapsed[0].textContent).toContain('completed');
        expect(po.byId('jump-failed')).toBeNull();
        expect(po.all('[data-id="node"].node-selected')[0].classList.contains('node-bad')).toBe(
            true
        );
        const before = po.all('[data-id="node"]').length;
        collapsed[0].dispatchEvent(new CustomEvent('click', { bubbles: true }));
        await flushPromises();
        expect(po.all('[data-id="node"]').length).toBeGreaterThan(before);
    });

    it('selects the running node when nothing failed', async () => {
        const po = await mount(runningSequence());
        const selected = po.all('[data-id="node"].node-selected');
        expect(selected).toHaveLength(1);
        expect(selected[0].classList.contains('node-run')).toBe(true);
    });

    it('shows a page strip inside a chunk node', async () => {
        const pages = [1, 2, 3].map(n =>
            step({
                chainSequence: 1,
                customJobId: 'p' + n,
                chunkRunId: 'run',
                chunkPage: n,
                chunkPages: 3,
                status: n === 2 ? 'FAILED' : 'COMPLETED'
            })
        );
        const po = await mount(sequence('chunky', pages));
        expect(po.all('[data-id="node"]')).toHaveLength(1);
        expect(po.all('[data-id="node"] .sq')).toHaveLength(3);
        expect(po.all('[data-id="node"]')[0].textContent).toContain('3 pages');
    });

    it('opens the failed node on arrival and switches the detail panel on click', async () => {
        const po = await mount(failedSequence());
        expect(po.byId('detail').textContent).toContain('UNABLE_TO_LOCK_ROW');
        expect(po.byId('detail').textContent).toContain('Commission split');
        po.all('[data-id="node"]')[0].dispatchEvent(new CustomEvent('click', { bubbles: true }));
        await flushPromises();
        expect(po.byId('detail').textContent).toContain('Reserve stock');
        po.all('[data-id="node"]')[0].dispatchEvent(new CustomEvent('click', { bubbles: true }));
        await flushPromises();
        expect(po.byId('detail')).toBeNull();
    });
});
