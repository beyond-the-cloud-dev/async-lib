import USER_LOCALE from '@salesforce/i18n/locale';
import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import {
    CAPS,
    currentRowKey,
    groupSteps,
    formatDuration,
    pageStripFor,
    delayOf,
    clockOf,
    statusOf
} from 'c/asyncJobTimelineModel';

const GLYPHS = { ok: '✓', bad: '✕', skip: '→', wait: '○', delay: '◷', run: '', retry: '↻' };
const OUTCOME_WORDS = { SUCCESS: 'succeeded', FAILURE: 'failed', COMPLETED: 'finished' };
const LANE_HEIGHT = 18;
const LANE_TOP = 28;

export default class AsyncChainMap extends LightningModal {
    @api sequence;

    selectedKey = null;
    focused = false;
    expandedRuns = new Set();
    connectors = [];
    connectorSignature = '';

    renderedCallback() {
        this.measureConnectors();
        this.focusFirstInterestingNode();
    }

    get rows() {
        return groupSteps(this.sequence?.steps || []);
    }

    get nameByCustomJobId() {
        const names = {};
        (this.sequence?.steps || []).forEach(step => {
            names[step.customJobId] = step.jobName || step.className;
        });
        return names;
    }

    get groups() {
        const top = this.rows.filter(row => row.depth === 0 && row.kind !== 'finalizer');
        const groups = [];
        let run = [];
        const flushRun = () => {
            const runKey = run.length ? 'run-' + run[0].key : null;
            const collapse =
                run.length > CAPS.mapCollapseRun &&
                top.length > CAPS.mapBoxes &&
                !this.expandedRuns.has(runKey);
            if (collapse) groups.push({ key: runKey, rows: run, collapsed: true });
            else run.forEach(row => groups.push({ key: row.key, rows: [row], collapsed: false }));
            run = [];
        };
        top.forEach(row => {
            if (row.status.key === 'ok') run.push(row);
            else {
                flushRun();
                groups.push({ key: row.key, rows: [row], collapsed: false });
            }
        });
        flushRun();
        return groups;
    }

    get columns() {
        const finalizers = this.rows.filter(row => row.kind === 'finalizer' && row.depth === 1);
        return this.groups.map(group => ({
            key: group.key,
            node: group.collapsed ? this.collapsedNodeOf(group) : this.nodeOf(group.rows[0]),
            finalizers: group.collapsed
                ? []
                : finalizers
                      .filter(row => row.step.parentCustomJobId === group.rows[0].step.customJobId)
                      .map(row => this.finalizerOf(row))
        }));
    }

    get arcs() {
        const keyByCustomJobId = new Map();
        this.groups.forEach(group =>
            group.rows.forEach(row => keyByCustomJobId.set(row.step.customJobId, group.key))
        );
        const arcs = [];
        this.rows
            .filter(row => row.depth === 0 && row.kind !== 'finalizer')
            .forEach(row => {
                this.dependenciesOf(row.step).forEach(dependency => {
                    const from = keyByCustomJobId.get(dependency.resolvedTargetCustomJobId);
                    const to = keyByCustomJobId.get(row.step.customJobId);
                    if (!from || !to || from === to) return;
                    const unmet = row.step.status === 'SKIPPED_DEPENDENCY';
                    const pending = ['wait', 'delay', 'run', 'retry'].includes(
                        statusOf(row.step).key
                    );
                    const state = unmet ? 'unmet' : pending ? 'pending' : 'met';
                    arcs.push({
                        key: `${row.key}-${dependency.resolvedTargetCustomJobId}`,
                        from,
                        to,
                        state,
                        label: `${OUTCOME_WORDS[dependency.requiredOutcome] || 'finished'} · ${
                            { unmet: 'not met', pending: 'pending', met: 'met' }[state]
                        }`
                    });
                });
            });
        return arcs;
    }

    get canvasStyle() {
        return `padding-top:${LANE_TOP + this.arcs.length * LANE_HEIGHT}px`;
    }

    get selectedRow() {
        return this.rows.find(row => row.key === this.selectedKey) || null;
    }

    get detail() {
        const row = this.selectedRow;
        if (!row) return null;
        const step = row.step;
        const lines = [
            ['Job', step.jobName || step.className],
            ['Class', step.className],
            ['Status', row.status.label],
            ['Position', step.chainSequence ? '#' + step.chainSequence : null],
            ['Started', this.formatted(step.startedAt)],
            ['Finished', this.formatted(step.finishedAt)],
            ['Attempts', step.retryAttempts ? step.retryAttempts + 1 : null],
            ['Exception', step.exceptionType],
            ['Message', step.exceptionMessage],
            ['Skip reason', step.skipReason],
            ['Requeue', step.requeueStatus],
            ['Records', (step.records || []).map(record => record.name).join(', ')]
        ].filter(([, value]) => value);
        return {
            title: step.jobName || step.className,
            lines: lines.map(([label, value]) => ({ label, value }))
        };
    }

    collapsedNodeOf(group) {
        const first = group.rows[0].step.chainSequence;
        const last = group.rows[group.rows.length - 1].step.chainSequence;
        return {
            key: group.key,
            className: 'node node-ok node-collapsed',
            glyphClass: 'glyph glyph-ok',
            glyphText: GLYPHS.ok,
            name: `${group.rows.length} completed`,
            title: 'Click to expand',
            sub: `steps ${first} to ${last} · click to expand`,
            tags: [],
            strip: null
        };
    }

    nodeOf(row) {
        const step = row.step;
        const addedAtRuntime = Boolean(step.addedByCustomJobId);
        const name = step.jobName || step.className;
        return {
            key: row.key,
            className:
                `node node-${row.status.key}` +
                (addedAtRuntime ? ' node-added' : '') +
                (row.key === this.selectedKey ? ' node-selected' : ''),
            glyphClass: `glyph glyph-${row.status.key}`,
            glyphText: GLYPHS[row.status.key],
            name,
            title: step.jobName ? step.className : name,
            sub: this.subOf(row),
            tags: this.tagsOf(row),
            strip: row.kind === 'chunk' ? this.stripOf(row) : null
        };
    }

    subOf(row) {
        const parts = [];
        if (row.step.chainSequence) parts.push('#' + row.step.chainSequence);
        if (row.kind === 'chunk') {
            const total = row.step.chunkPages || row.pages.length;
            parts.push(`${total} page${total === 1 ? '' : 's'}`);
        }
        if (row.status.key === 'ok') {
            const duration = formatDuration(
                Date.parse(row.step.finishedAt) - Date.parse(row.step.startedAt)
            );
            parts.push(duration || 'completed');
        } else if (delayOf(row).until) {
            parts.push(`delayed · until ${clockOf(delayOf(row).until)}`);
        } else if (delayOf(row).plannedMinutes) {
            parts.push(`enqueued · delay ${delayOf(row).plannedMinutes} min`);
        } else if (row.step.retryAttempts) {
            parts.push(`${row.status.label.toLowerCase()} · attempt ${row.step.retryAttempts + 1}`);
        } else {
            parts.push(row.status.label.toLowerCase());
        }
        return parts.join(' · ');
    }

    tagsOf(row) {
        const tags = [];
        const step = row.step;
        if (step.priority !== null && step.priority !== undefined) tags.push('P' + step.priority);
        if (step.addedByCustomJobId)
            tags.push('↳ added by ' + (this.nameByCustomJobId[step.addedByCustomJobId] || '?'));
        return tags;
    }

    stripOf(row) {
        const strip = pageStripFor(row);
        return {
            summary: strip.summary,
            squares: (strip.squares || []).map(square => ({
                page: square.page,
                className: `sq sq-${square.key}`
            }))
        };
    }

    finalizerOf(row) {
        return {
            key: row.key,
            className: `fin fin-${row.status.key}`,
            glyphClass: `glyph glyph-sm glyph-${row.status.key}`,
            glyphText: GLYPHS[row.status.key],
            name: row.step.jobName || row.step.className,
            title: `finalizer · ${row.status.label}`
        };
    }

    focusFirstInterestingNode() {
        if (this.focused) return;
        this.focused = true;
        const currentKey = currentRowKey(this.rows);
        const node = this.firstNodeMatching(
            candidate =>
                candidate.classList.contains('node-bad') || candidate.dataset.key === currentKey
        );
        if (!node) return;
        if (typeof node.scrollIntoView === 'function')
            node.scrollIntoView({ inline: 'center', block: 'nearest' });
        this.selectedKey = node.dataset.key;
    }

    firstNodeMatching(matches) {
        return [...(this.refs.canvas?.querySelectorAll('[data-id="node"]') || [])].find(matches);
    }

    // Node positions only exist after render, so the connectors are drawn one pass later and
    // re-set only when they moved, which keeps renderedCallback from re-entering forever.
    measureConnectors() {
        const canvas = this.refs.canvas;
        if (!canvas) return;
        const origin = canvas.getBoundingClientRect();
        const nodes = new Map();
        canvas.querySelectorAll('[data-id="node"]').forEach(node => {
            const rect = node.getBoundingClientRect();
            nodes.set(node.dataset.key, {
                x: rect.left - origin.left + rect.width / 2,
                top: rect.top - origin.top
            });
        });
        const connectors = this.arcs.map((arc, index) => {
            const from = nodes.get(arc.from) || { x: 0, top: 0 };
            const to = nodes.get(arc.to) || { x: 0, top: 0 };
            const laneY = LANE_TOP + (this.arcs.length - 1 - index) * LANE_HEIGHT - 8;
            const step = 6;
            const fromX = from.x + (from.x < to.x ? -step : step);
            const toX = to.x + (from.x < to.x ? step : -step);
            return {
                key: arc.key,
                d: `M ${fromX} ${from.top} V ${laneY} H ${toX} V ${to.top - 7}`,
                head: `M ${toX - 4} ${to.top - 8} L ${toX + 4} ${to.top - 8} L ${toX} ${to.top - 1} z`,
                className: `arc arc-${arc.state}`,
                headClass: `arrow arrow-${arc.state}`,
                labelX: (fromX + toX) / 2,
                labelY: laneY - 3,
                label: arc.label
            };
        });
        const signature = JSON.stringify(connectors);
        if (signature === this.connectorSignature) return;
        this.connectorSignature = signature;
        this.connectors = connectors;
    }

    dependenciesOf(step) {
        if (!step.dependencies) return [];
        try {
            const parsed = JSON.parse(step.dependencies);
            return Array.isArray(parsed) ? parsed : [];
        } catch {
            return [];
        }
    }

    formatted(iso) {
        const at = Date.parse(iso);
        if (!iso || Number.isNaN(at)) return null;
        return new Date(at).toLocaleString(USER_LOCALE, {
            day: 'numeric',
            month: 'short',
            hour: '2-digit',
            minute: '2-digit',
            second: '2-digit'
        });
    }

    selectNode(event) {
        const key = event.currentTarget.dataset.key;
        if (key.startsWith('run-')) {
            this.expandedRuns = new Set([...this.expandedRuns, key]);
            return;
        }
        this.selectedKey = key === this.selectedKey ? null : key;
    }

    keySelectNode(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.selectNode(event);
        }
    }

    clearSelection() {
        this.selectedKey = null;
    }

    handleClose() {
        this.close();
    }
}
