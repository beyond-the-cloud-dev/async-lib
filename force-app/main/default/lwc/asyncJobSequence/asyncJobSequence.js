import { LightningElement, api } from 'lwc';
import {
    CAPS,
    groupSteps,
    sequenceSummary,
    collapseCompletedRuns,
    currentRowKey,
    formatDuration,
    relativeTime,
    expectedPagesOf,
    pageStripStyle,
    pluralOf,
    rowKeyOf,
    dotsFit,
    clockOf
} from 'c/asyncJobTimelineModel';

const BADGES = {
    running: 'Running',
    queued: 'Queued',
    delayed: 'Delayed',
    failed: 'Failed',
    stopped: 'Stopped',
    completed: 'Completed'
};
const IN_FLIGHT = new Set(['running', 'queued', 'delayed']);
const CLOCK_MS = 1000;
const STATUS_MARKS = {
    queued: 'hollow',
    delayed: 'hollow',
    completed: 'check',
    failed: 'cross',
    stopped: 'square'
};
const RUNNING_MARKS = { executing: 'dot', waiting: 'hollow', retrying: 'refresh' };
const ACTIVITY_TEXT = {
    executing: 'a step is executing',
    waiting: 'waiting for the platform',
    retrying: 'waiting for a retry'
};
export default class AsyncJobSequence extends LightningElement {
    @api sequence;
    @api canRequeue = false;
    @api defaultExpanded = false;
    @api isNew = false;
    @api pageRecordId;
    @api highlight = { added: [], changed: [] };

    @api
    get collapseToken() {
        return this.token;
    }
    set collapseToken(value) {
        if (value !== this.token) this.expandedOverride = null;
        this.token = value;
    }

    token = 0;
    expandedOverride = null;
    expandedGaps = new Set();
    headerTopBeforeToggle;
    clockTimer;
    now = Date.now();

    connectedCallback() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.clockTimer = setInterval(() => this.tickClock(), CLOCK_MS);
    }

    // The parent can only keep the header in place if it learns how far it moved before the
    // browser paints; renderedCallback runs right after the DOM patch, inside the same pass.
    renderedCallback() {
        if (this.headerTopBeforeToggle === undefined) return;
        const delta = this.template.host.getBoundingClientRect().top - this.headerTopBeforeToggle;
        this.headerTopBeforeToggle = undefined;
        this.dispatchEvent(
            new CustomEvent('sequencetoggle', { detail: { open: this.isExpanded, delta } })
        );
    }

    disconnectedCallback() {
        clearInterval(this.clockTimer);
    }

    @api
    expand() {
        this.expandedOverride = true;
    }

    @api
    scrollTo() {
        if (typeof this.template.host?.scrollIntoView === 'function')
            this.template.host.scrollIntoView({ block: 'start', behavior: 'smooth' });
    }

    targetRowKey = null;

    get rows() {
        return groupSteps(this.sequence?.steps || []);
    }

    get summary() {
        return sequenceSummary(this.rows);
    }

    get nameByCustomJobId() {
        const names = {};
        (this.sequence?.steps || []).forEach(step => {
            names[step.customJobId] = step.jobName || step.className;
        });
        return names;
    }

    get isInFlight() {
        return IN_FLIGHT.has(this.summary.status);
    }

    get isExpanded() {
        if (this.expandedOverride !== null) return this.expandedOverride;
        return Boolean(this.defaultExpanded);
    }

    get chainClass() {
        return this.isExpanded ? 'chain is-open' : 'chain';
    }

    get toggleIcon() {
        return this.isExpanded ? 'utility:chevrondown' : 'utility:chevronright';
    }

    get caretLabel() {
        return this.isExpanded ? 'Collapse' : 'Expand';
    }

    get badgeLabel() {
        return BADGES[this.summary.status];
    }

    get badgeClass() {
        return `chain-badge chain-badge-${this.summary.status}`;
    }

    get badgeMarkClass() {
        const { status, activity } = this.summary;
        const mark = status === 'running' ? RUNNING_MARKS[activity] : STATUS_MARKS[status];
        return `mark mark-${mark}`;
    }

    get badgeRetrying() {
        const { status, activity } = this.summary;
        return status === 'running' && activity === 'retrying';
    }

    get failedSoFar() {
        const { status, failedSteps } = this.summary;
        return status === 'running' ? failedSteps : 0;
    }

    get delayedTail() {
        const { status, activity, delayedUntil } = this.summary;
        return status === 'running' && activity !== 'executing' && Boolean(delayedUntil);
    }

    get badgeTitle() {
        const { status, activity, failedSteps } = this.summary;
        if (status === 'running') {
            const failed = failedSteps ? ` · ${failedSteps} failed so far` : '';
            return `Running · ${ACTIVITY_TEXT[activity]}${failed}`;
        }
        if (status === 'queued') return 'Queued · nothing has started yet';
        if (status === 'delayed') return 'Delayed · nothing has started yet';
        return failedSteps ? `${BADGES[status]} · ${failedSteps} failed` : BADGES[status];
    }

    get title() {
        return this.sequence?.name || 'Async jobs';
    }

    get replayOf() {
        const replayed = (this.sequence?.steps || []).find(step => step.requeuedFrom);
        if (!replayed) return null;
        return `Replay of ${replayed.requeuedFromName || 'an earlier result'}`;
    }

    get started() {
        return relativeTime(this.sequence?.startedAt, this.now);
    }

    get startedText() {
        return this.started?.text || '';
    }

    get startedFull() {
        return this.started?.full || '';
    }

    get subline() {
        const summary = this.summary;
        const parts = [];
        if (summary.durationMs !== null && !this.isInFlight)
            parts.push(formatDuration(summary.durationMs));
        if (this.summary.status === 'delayed') {
            parts.push(`starts at ${clockOf(summary.delayedUntil)}`);
        } else if (this.delayedTail) {
            parts.push(`next step at ${clockOf(summary.delayedUntil)}`);
        } else if (this.isInFlight && this.sequence?.startedAt) {
            const elapsed = this.now - Date.parse(this.sequence.startedAt);
            const verb = summary.status === 'running' ? 'running' : 'queued for';
            if (elapsed > 0) parts.push(`${verb} ${formatDuration(elapsed)}`);
        }
        parts.push(`${summary.total} step${summary.total === 1 ? '' : 's'}`);
        const pages = this.rows
            .filter(row => row.kind === 'chunk')
            .reduce((sum, row) => sum + expectedPagesOf(row), 0);
        if (pages) parts.push(`${pages} page${pages === 1 ? '' : 's'}`);
        return parts.join(' · ');
    }

    get progressText() {
        const progress = this.summary.progress;
        const parts = [];
        if (progress.steps)
            parts.push(
                `${progress.stepsCompleted} of ${pluralOf(progress.steps, 'step')} completed`
            );
        if (progress.pages)
            parts.push(`${progress.pagesDone} of ${pluralOf(progress.pages, 'page')}`);
        if (progress.failed) parts.push(`${progress.failed} failed`);
        if (progress.skipped) parts.push(`${progress.skipped} skipped`);
        if (progress.running) parts.push(`${progress.running} running`);
        if (progress.waiting) parts.push(`${progress.waiting} waiting`);
        return parts.join(' · ');
    }

    get percentLabel() {
        return `${this.summary.percent} %`;
    }

    get barSegments() {
        const progress = this.summary.progress;
        const width = count => (progress.total === 0 ? 0 : (count / progress.total) * 100);
        return [
            { key: 'ok', className: 'seg seg-ok', style: `width:${width(progress.completed)}%` },
            { key: 'bad', className: 'seg seg-bad', style: `width:${width(progress.failed)}%` },
            { key: 'skip', className: 'seg seg-skip', style: `width:${width(progress.skipped)}%` },
            { key: 'run', className: 'seg seg-run', style: `width:${width(progress.running)}%` }
        ].filter(segment => !segment.style.endsWith(':0%'));
    }

    get dotsFit() {
        return dotsFit(this.rows);
    }

    get dots() {
        return this.rows.map(row => {
            if (row.kind === 'chunk')
                return { key: row.key, className: 'dot dot-strip', style: pageStripStyle(row) };
            return { key: row.key, className: `dot dot-${row.status.key}`, style: '' };
        });
    }

    get replayableIds() {
        return this.rows
            .filter(row => row.kind !== 'chunk' && ['bad', 'skip'].includes(row.status.key))
            .filter(row => row.step.requeueStatus === 'Stored')
            .map(row => row.step.id);
    }

    get showRequeueFailed() {
        return this.canRequeue && !this.isInFlight && this.replayableIds.length > 0;
    }

    get requeueCount() {
        return String(this.replayableIds.length);
    }

    get requeueLabel() {
        const count = this.replayableIds.length;
        return `Requeue failed step${count === 1 ? '' : 's'} (${count})`;
    }

    get currentKey() {
        return this.isInFlight ? currentRowKey(this.rows) : null;
    }

    get visibleRows() {
        let rows = collapseCompletedRuns(this.rows);
        rows = rows.flatMap(row => {
            return row.kind === 'gap' && this.expandedGaps.has(row.key) ? row.hiddenRows : [row];
        });
        const steps = rows.filter(row => row.kind !== 'gap');
        if (steps.length > CAPS.stepsMax) {
            let kept = 0;
            rows = rows.filter(row => {
                if (row.kind === 'gap') return true;
                kept += 1;
                return kept <= CAPS.stepsMax;
            });
        }
        return rows.map((row, index) => ({
            ...this.viewOf(row),
            isLastRow: index === rows.length - 1
        }));
    }

    get capNote() {
        const total = this.rows.length;
        return total > CAPS.stepsMax
            ? `Showing ${CAPS.stepsMax} of ${total} steps. Open the first result and follow the chain for the rest.`
            : null;
    }

    tickClock() {
        const now = Date.now();
        const startedTextChanges =
            relativeTime(this.sequence?.startedAt, now)?.text !== this.startedText;
        if (this.isInFlight || startedTextChanges) this.now = now;
    }

    viewOf(row) {
        if (row.kind === 'gap') {
            return {
                key: row.key,
                isGap: true,
                label: `${pluralOf(row.hiddenCount, 'completed step')} hidden · Show`
            };
        }
        return {
            key: row.key,
            isGap: false,
            row,
            isNew: this.highlight?.added?.includes(row.key) || false,
            isChanged: this.highlight?.changed?.includes(row.key) || false,
            isCurrent: row.key === this.currentKey,
            isTarget: row.key === this.targetRowKey
        };
    }

    handleTagTarget(event) {
        this.targetRowKey = rowKeyOf(this.rows, event.detail.jobId);
    }

    toggleExpanded(event) {
        event?.stopPropagation();
        const open = !this.isExpanded;
        this.headerTopBeforeToggle = this.template.host.getBoundingClientRect().top;
        this.expandedOverride = open;
        if (!open) this.expandedGaps = new Set();
    }

    handleHeadClick() {
        this.toggleExpanded();
    }

    stopHeadClick(event) {
        event.stopPropagation();
    }

    expandGap(event) {
        const key = event.currentTarget.dataset.key;
        this.expandedGaps = new Set([...this.expandedGaps, key]);
    }

    handleRequeueFailed() {
        const count = this.replayableIds.length;
        this.dispatchEvent(
            new CustomEvent('requeue', {
                detail: {
                    resultIds: this.replayableIds,
                    label: `${count} failed step${count === 1 ? '' : 's'} of ${this.title}`
                }
            })
        );
    }

    handleStepRequeue(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('requeue', { detail: event.detail }));
    }

    handleOpenReplay(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('openreplay', { detail: event.detail }));
    }

    handleMenu(event) {
        const chainId = this.sequence.chainId;
        const first = this.rows[0]?.step;
        const actions = {
            map: () => this.dispatchEvent(new CustomEvent('openmap', { detail: { chainId } })),
            result: () =>
                first &&
                this.dispatchEvent(
                    new CustomEvent('openresult', { detail: { resultId: first.id } })
                ),
            copy: () => navigator.clipboard?.writeText(chainId).catch(() => {})
        };
        actions[event.detail.value]?.();
    }
}
