import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import load from '@salesforce/apex/AsyncJobTimelineController.load';
import poll from '@salesforce/apex/AsyncJobTimelineController.poll';
import requeue from '@salesforce/apex/AsyncJobTimelineController.requeue';
import ASYNC_RESULT from '@salesforce/schema/AsyncResult__c';
import LOGO from '@salesforce/resourceUrl/AsyncLibLogo';
import AsyncChainMap from 'c/asyncChainMap';
import {
    POLL,
    RANGES,
    VERSION,
    groupSteps,
    sequenceSummary,
    diffRows,
    pollDelayFor
} from 'c/asyncJobTimelineModel';

const HIGHLIGHT_MS = 10000;
const LOAD_LINE_DELAY_MS = 300;
const CLOCK_MS = 30000;
const CARD_CHROME_PX = 96;
const COLLAPSED_ROW_PX = 66;
const DEFAULT_DAYS = 7;
const PREFETCH_CHAINS = 50;
const NAMESPACE_PREFIX = ASYNC_RESULT.objectApiName.replace(/AsyncResult__c$/, '');
const IN_FLIGHT = new Set(['running', 'queued', 'delayed']);
const FILTERS = {
    all: () => true,
    inflight: summary => IN_FLIGHT.has(summary.status),
    failed: summary => summary.status === 'failed' || summary.status === 'stopped',
    completed: summary => summary.status === 'completed'
};

export default class AsyncJobTimeline extends NavigationMixin(LightningElement) {
    @api recordId;
    @api cardTitle = 'Async Jobs';
    @api daysBack = DEFAULT_DAYS;
    @api chainsPerPage = 0;
    @api maxHeight = 600;
    @api liveRefreshOff = false;
    @api followNewRuns = false;

    page;
    loading = true;
    busy = false;
    refreshing = false;
    error;
    openChainIds = new Set();
    autoOpenConsidered = new Set();
    knownInFlight = new Set();
    freshChainIds = new Set();
    collapseToken = 0;
    followOverride = null;
    fillerPx = 0;
    pendingScrollTop;
    filter = 'all';
    pageIndex = 0;
    blockIndex = 0;
    rangeOverride = null;
    showLegend = false;
    announcement = '';
    highlightByChain = {};
    paused = false;
    watchedChainIds = new Set();
    allChainsBlock = null;
    heldSequences = null;
    showLoadLine = false;
    servedFromMemory = false;
    refreshFailed = false;
    stopped = false;
    stoppedReason;
    loadFailed = false;
    pollFailures = 0;
    pollTimer;
    highlightTimer;
    clockTimer;
    pollStartedAt;
    latestRequestId = 0;
    replayGraceUntil = 0;
    lastCheckedAt;
    now = Date.now();
    previousRowsByChain;
    logoUrl = LOGO;
    versionLabel = `v${VERSION}`;
    docsUrl = 'https://async.beyondthecloud.dev';
    makerUrl = 'https://beyondthecloud.dev';
    brandTitle = 'Built by Beyond The Cloud. Need help with async Apex? Talk to us.';

    connectedCallback() {
        document.addEventListener('visibilitychange', this.handleVisibility);
        this.pollStartedAt = Date.now();
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.clockTimer = setInterval(() => {
            this.now = Date.now();
        }, CLOCK_MS);
        this.reload();
    }

    renderedCallback() {
        if (this.focusLegendClose) {
            this.focusLegendClose = false;
            this.refs.legendClose?.focus();
        }
        if (this.pendingScrollTop === undefined) return;
        this.refs.scroller.scrollTop = this.pendingScrollTop;
        this.pendingScrollTop = undefined;
    }

    disconnectedCallback() {
        this.closeLegend();
        document.removeEventListener('visibilitychange', this.handleVisibility);
        clearTimeout(this.pollTimer);
        clearTimeout(this.highlightTimer);
        clearTimeout(this.loadLineTimer);
        clearInterval(this.clockTimer);
    }

    get days() {
        if (this.rangeOverride !== null) return this.rangeOverride;
        const configured = Number(this.daysBack);
        const blank = this.daysBack === undefined || this.daysBack === null || this.daysBack === '';
        return blank || !Number.isFinite(configured) ? DEFAULT_DAYS : configured;
    }

    get pageSize() {
        const configured = Number(this.chainsPerPage);
        if (Number.isFinite(configured) && configured > 0) return configured;
        const height = Number(this.maxHeight) || 600;
        return Math.max(3, Math.floor((height - CARD_CHROME_PX) / COLLAPSED_ROW_PX));
    }

    get isFollowing() {
        return this.followOverride ?? Boolean(this.followNewRuns);
    }

    get followTitle() {
        return this.isFollowing
            ? 'Following: a new chain in flight opens by itself and the others collapse.'
            : 'Not following: a new chain in flight is only flagged.';
    }

    get rowsByChain() {
        return (this.page?.sequences || []).map(sequence => ({
            sequence,
            rows: groupSteps(sequence.steps)
        }));
    }

    get summaries() {
        return this.rowsByChain.map(({ sequence, rows }) => ({
            sequence,
            summary: sequenceSummary(rows)
        }));
    }

    get localOffset() {
        return this.pageIndex * this.pageSize - this.blockIndex * PREFETCH_CHAINS;
    }

    get visibleSequences() {
        if (this.heldSequences) return this.heldSequences;
        return (this.page?.sequences || []).slice(
            this.localOffset,
            this.localOffset + this.pageSize
        );
    }

    get sequenceViews() {
        return this.visibleSequences.map(sequence => ({
            key: sequence.chainId,
            sequence,
            defaultExpanded: this.openChainIds.has(sequence.chainId),
            isNew: this.freshChainIds.has(sequence.chainId),
            highlight: this.highlightByChain[sequence.chainId] || { added: [], changed: [] }
        }));
    }

    get fillerStyle() {
        return this.fillerPx > 0 ? `height:${this.fillerPx}px` : '';
    }

    get chips() {
        const counts = {
            all: 0,
            inflight: 0,
            failed: 0,
            completed: 0,
            ...(this.page?.counts || {})
        };
        if (!this.page?.counts) {
            this.summaries.forEach(({ summary }) => {
                Object.keys(counts).forEach(name => {
                    if (FILTERS[name](summary)) counts[name] += 1;
                });
            });
        }
        const pulsing =
            !this.liveRefreshOff && !this.loadFailed && !this.paused && !this.stoppedReason;
        return [
            { name: 'all', label: 'All' },
            { name: 'inflight', label: 'In flight' },
            { name: 'failed', label: 'Failed' },
            { name: 'completed', label: 'Completed' }
        ].map(chip => ({
            ...chip,
            id: 'chip-' + chip.name,
            count: counts[chip.name],
            live: chip.name === 'inflight' && counts.inflight > 0,
            dotClass: pulsing ? 'chip-dot' : 'chip-dot is-paused',
            className: {
                chip: true,
                active: this.filter === chip.name,
                'chip-live': chip.name === 'inflight' && counts.inflight > 0
            }
        }));
    }

    get rangeOptions() {
        return RANGES.map(range => ({
            value: String(range.days),
            label: range.label,
            checked: range.days === this.days
        }));
    }

    get rangeShortLabel() {
        return this.rangeLabel.replace(/^Last /, '');
    }

    get rangeLabel() {
        const known = RANGES.find(range => range.days === this.days);
        return known ? known.label : `Last ${this.days} days`;
    }

    get rangeText() {
        return this.rangeLabel.charAt(0).toLowerCase() + this.rangeLabel.slice(1);
    }

    get scrollerStyle() {
        const height = Number(this.maxHeight);
        return height > 0 ? `height:${height}px;overflow-y:auto` : '';
    }

    get hasSequences() {
        return (this.page?.sequences || []).length > 0 || this.filter !== 'all';
    }

    get showEmpty() {
        return !this.loading && !this.error && !this.hasSequences;
    }

    get emptyText() {
        const what = this.filter === 'all' ? 'async jobs' : `${this.filter} sequences`;
        return this.days === 0
            ? `No ${what} for this record.`
            : `No ${what} for this record in the ${this.rangeText}.`;
    }

    get olderLabel() {
        const count = this.page?.olderChainCount || 0;
        if (count === 0 || this.days === 0) return null;
        return `${count} older sequence${count === 1 ? '' : 's'} before the ${this.rangeText}`;
    }

    get totalChains() {
        return this.page?.totalChainCount || (this.page?.sequences || []).length;
    }

    get showPager() {
        return this.totalChains > this.pageSize;
    }

    get pagerLabel() {
        const from = this.pageIndex * this.pageSize + 1;
        const to = this.pageIndex * this.pageSize + this.visibleSequences.length;
        return `${from}-${to} of ${this.totalChains}`;
    }

    get isFirstPage() {
        return this.pageIndex === 0;
    }

    get isLastPage() {
        return (this.pageIndex + 1) * this.pageSize >= this.totalChains;
    }

    get canRequeue() {
        return Boolean(this.page?.canRequeue);
    }

    get inFlight() {
        return this.summaries.some(({ summary }) => IN_FLIGHT.has(summary.status));
    }

    get isStale() {
        if (this.inFlight || !this.lastCheckedAt) return false;
        return this.now - this.lastCheckedAt > POLL.staleMinutes * 60 * 1000;
    }

    get refreshVariant() {
        return this.isStale || this.stopped ? 'brand' : 'border';
    }

    get refreshTitle() {
        return this.isStale ? 'Not checked for a while · refresh now' : 'Refresh now';
    }

    get liveState() {
        if (this.refreshFailed)
            return {
                className: 'live-dot stale',
                text: 'Could not refresh · showing what was loaded'
            };
        if (this.refreshing) return { className: 'live-dot', text: 'Refreshing…' };
        if (this.stopped)
            return {
                className: 'live-dot stopped',
                text: `Paused after ${this.stoppedReason} · refresh to continue`
            };
        if (this.paused)
            return { className: 'live-dot stopped', text: 'Paused while this tab is hidden' };
        if (this.isStale) {
            const minutes = Math.floor((this.now - this.lastCheckedAt) / 60000);
            return {
                className: 'live-dot stale',
                text: `Last checked ${minutes} min ago · refresh to see newer jobs`
            };
        }
        if (!this.inFlight && this.inReplayGrace)
            return {
                className: 'live-dot',
                text: 'Live · waiting for the replay',
                title: 'A replay without progress tracking has no rows until it settles'
            };
        if (!this.inFlight)
            return {
                className: 'live-dot idle',
                text: 'Idle',
                title: 'Nothing in flight. The card refreshes when you come back to it or press refresh'
            };
        const live = {
            className: 'live-dot',
            text: 'Live',
            title: `Checks every ${POLL.running / 1000} s while a step runs, every ${POLL.queued / 1000} s while it waits in the queue`
        };
        const fresh = this.freshChainIds.size;
        if (fresh > 0)
            return {
                ...live,
                text: `Live · ${fresh} new sequence${fresh === 1 ? '' : 's'} running`
            };
        const delay = this.currentPollDelay;
        if (delay > POLL.queued)
            return {
                className: 'live-dot',
                text: 'Live · next check',
                at: new Date(Date.now() + delay).toISOString(),
                title: 'Nothing can change before the delay or retry is due'
            };
        return live;
    }

    get liveClass() {
        return this.isStale || this.stopped ? 'live is-stale' : 'live';
    }

    get currentPollDelay() {
        const rows = this.rowsByChain.flatMap(({ rows: chainRows }) => chainRows);
        return pollDelayFor(rows, Date.now()) || POLL.queued;
    }

    get showLive() {
        return !this.liveRefreshOff && Boolean(this.page);
    }

    get legendLabel() {
        return this.showLegend ? 'Hide legend' : 'Legend';
    }

    get helpVariant() {
        return this.showLegend ? 'brand' : 'border';
    }

    get bodyClass() {
        return this.showLegend ? 'body legend-open' : 'body';
    }

    get inReplayGrace() {
        return Date.now() < this.replayGraceUntil;
    }

    handleVisibility = () => this.onVisibilityChange();

    closeLegendOnEscape = event => {
        if (event.key === 'Escape') this.closeLegend();
    };

    async reload({ silent = false } = {}) {
        this.latestRequestId += 1;
        const requestId = this.latestRequestId;
        if (!silent) this.loading = true;
        this.busy = true;
        try {
            const result = await load({
                request: {
                    recordId: this.recordId,
                    daysBack: this.days,
                    chainLimit: PREFETCH_CHAINS,
                    chainOffset: this.blockIndex * PREFETCH_CHAINS,
                    statusFilter: this.filter,
                    keepChainIds: [...this.watchedChainIds]
                }
            });
            if (requestId !== this.latestRequestId) return;
            this.error = undefined;
            this.loadFailed = false;
            this.refreshFailed = false;
            this.lastCheckedAt = Date.now();
            this.applyPage(result);
        } catch (failure) {
            if (requestId !== this.latestRequestId) return;
            if (this.servedFromMemory) this.refreshFailed = true;
            else this.error = failure?.body?.message || failure?.message || String(failure);
            this.loadFailed = true;
        }
        this.servedFromMemory = false;
        this.releaseList();
        this.loading = false;
        this.busy = false;
        this.refreshing = false;
        this.schedulePoll();
    }

    handleFollowChange(event) {
        this.followOverride = event.detail.checked;
    }

    toggleFollow() {
        this.followOverride = !this.isFollowing;
    }

    trackInFlight(sequences) {
        const firstLook = !this.page;
        const inFlight = sequences.filter(sequence =>
            IN_FLIGHT.has(sequenceSummary(groupSteps(sequence.steps)).status)
        );
        const newcomers = inFlight.filter(sequence => !this.knownInFlight.has(sequence.chainId));
        inFlight.forEach(sequence => this.knownInFlight.add(sequence.chainId));
        if (this.isFollowing && !firstLook && newcomers.length) {
            this.openChainIds = new Set([newcomers[0].chainId]);
            this.collapseToken += 1;
            return;
        }
        this.autoOpenFirstRunning(sequences);
        if (firstLook) return;
        newcomers
            .filter(sequence => !this.openChainIds.has(sequence.chainId))
            .forEach(sequence => this.freshChainIds.add(sequence.chainId));
        this.freshChainIds = new Set(this.freshChainIds);
    }

    autoOpenFirstRunning(sequences) {
        if (this.filter !== 'all' || this.pageIndex !== 0) return;
        const unconsidered = sequences
            .slice(0, this.pageSize)
            .filter(sequence => sequenceSummary(groupSteps(sequence.steps)).status === 'running')
            .filter(sequence => !this.autoOpenConsidered.has(sequence.chainId));
        unconsidered.forEach(sequence => this.autoOpenConsidered.add(sequence.chainId));
        if (unconsidered.length && this.openChainIds.size === 0)
            this.openChainIds = new Set([unconsidered[0].chainId]);
    }

    rememberOpen(chainId, open) {
        const opened = new Set(this.openChainIds);
        if (open) opened.add(chainId);
        else opened.delete(chainId);
        this.openChainIds = opened;
    }

    holdListUntilLoaded() {
        this.heldSequences = this.visibleSequences;
        clearTimeout(this.loadLineTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.loadLineTimer = setTimeout(() => {
            this.showLoadLine = true;
        }, LOAD_LINE_DELAY_MS);
    }

    releaseList() {
        clearTimeout(this.loadLineTimer);
        this.heldSequences = null;
        this.showLoadLine = false;
    }

    get holdsEveryChain() {
        return Boolean(this.allChainsBlock) && !this.allChainsBlock.hasMore;
    }

    showFilteredFromMemory() {
        const sequences = this.allChainsBlock.sequences.filter(sequence =>
            FILTERS[this.filter](sequenceSummary(groupSteps(sequence.steps)))
        );
        this.servedFromMemory = true;
        this.page = {
            ...this.allChainsBlock,
            sequences,
            totalChainCount: sequences.length
        };
        if (this.filter === 'inflight')
            sequences.forEach(sequence => this.watchedChainIds.add(sequence.chainId));
    }

    keepAllChainsFresh(result) {
        if (this.filter === 'all' && this.blockIndex === 0) {
            this.allChainsBlock = result;
            return;
        }
        if (!this.allChainsBlock) return;
        const fresherByChain = new Map(
            (result.sequences || []).map(sequence => [sequence.chainId, sequence])
        );
        const knownChainIds = new Set(
            this.allChainsBlock.sequences.map(sequence => sequence.chainId)
        );
        const startedSinceTheBlockLoaded = (result.sequences || []).filter(
            sequence => !knownChainIds.has(sequence.chainId)
        );
        this.allChainsBlock = {
            ...this.allChainsBlock,
            counts: result.counts || this.allChainsBlock.counts,
            sequences: [
                ...startedSinceTheBlockLoaded,
                ...this.allChainsBlock.sequences.map(
                    sequence => fresherByChain.get(sequence.chainId) || sequence
                )
            ]
        };
    }

    applyPage(result) {
        this.keepAllChainsFresh(result);
        const rowsByChain = new Map();
        const highlightByChain = {};
        const announcements = [];
        (result.sequences || []).forEach(sequence => {
            const rows = groupSteps(sequence.steps);
            rowsByChain.set(sequence.chainId, rows);
            const diff = diffRows(this.previousRowsByChain?.get(sequence.chainId), rows);
            highlightByChain[sequence.chainId] = {
                added: [...diff.added],
                changed: [...diff.changed]
            };
            rows.forEach(row => {
                const name = row.step.jobName || row.step.className;
                if (diff.added.has(row.key)) announcements.push(`${name} added`);
                else if (diff.changed.has(row.key))
                    announcements.push(`${name} is now ${row.status.label}`);
            });
        });
        this.previousRowsByChain = rowsByChain;
        this.highlightByChain = highlightByChain;
        this.trackInFlight(result.sequences || []);
        if (this.filter === 'inflight')
            (result.sequences || []).forEach(sequence =>
                this.watchedChainIds.add(sequence.chainId)
            );
        this.page = result;
        this.fillerPx = 0;
        if (announcements.length) {
            this.announcement = announcements.join('. ');
            clearTimeout(this.highlightTimer);
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            this.highlightTimer = setTimeout(() => {
                this.highlightByChain = {};
                this.announcement = '';
            }, HIGHLIGHT_MS);
        }
    }

    schedulePoll(delayOverride) {
        clearTimeout(this.pollTimer);
        if (this.liveRefreshOff || !this.page || this.loadFailed || this.paused) return;
        if (!this.inFlight && !this.inReplayGrace) return;
        if (Date.now() - this.pollStartedAt > POLL.maxMinutes * 60 * 1000) {
            this.stopPolling(`${POLL.maxMinutes} minutes`);
            return;
        }
        this.stopped = false;
        const delay = delayOverride ?? (this.inFlight ? this.currentPollDelay : POLL.queued);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.pollTimer = setTimeout(() => this.tick(), delay);
    }

    async tick() {
        try {
            const result = await poll({
                recordId: this.recordId,
                chainIds: (this.page?.sequences || []).map(sequence => sequence.chainId)
            });
            this.lastCheckedAt = Date.now();
            if (result.fingerprint !== this.page.fingerprint) {
                await this.reload({ silent: true });
                return;
            }
            this.applyApexJobStatuses(result.apexJobStatusById || {});
            this.error = undefined;
            this.pollFailures = 0;
        } catch (failure) {
            this.error = failure?.body?.message || failure?.message || String(failure);
            this.pollFailures += 1;
            if (this.pollFailures >= POLL.maxFailures) {
                this.stopPolling(`${POLL.maxFailures} failed checks`);
                return;
            }
        }
        this.schedulePoll();
    }

    stopPolling(reason) {
        this.stopped = true;
        this.stoppedReason = reason;
    }

    applyApexJobStatuses(statusById) {
        let changed = false;
        const sequences = this.page.sequences.map(sequence => ({
            ...sequence,
            steps: sequence.steps.map(step => {
                const status = statusById[step.salesforceJobId];
                if (step.status !== 'ENQUEUED' || !status || status === step.apexJobStatus)
                    return step;
                changed = true;
                return { ...step, apexJobStatus: status };
            })
        }));
        if (changed) this.page = { ...this.page, sequences };
    }

    onVisibilityChange() {
        this.paused = document.visibilityState === 'hidden';
        clearTimeout(this.pollTimer);
        if (this.paused) return;
        this.now = Date.now();
        if ((this.inFlight || this.inReplayGrace) && !this.liveRefreshOff && !this.loadFailed)
            this.tick();
    }

    refresh() {
        this.stopped = false;
        this.pollFailures = 0;
        this.pollStartedAt = Date.now();
        this.refreshing = true;
        this.reload({ silent: true });
    }

    handleSequenceToggle(event) {
        const card = event.target;
        this.rememberOpen(card.sequence?.chainId, event.detail?.open);
        this.freshChainIds.delete(card.sequence?.chainId);
        this.freshChainIds = new Set(this.freshChainIds);
        const delta = event.detail?.delta || 0;
        if (delta === 0) return;
        const scroller = this.refs.scroller;
        const target = scroller.scrollTop + delta;
        const maxScroll = scroller.scrollHeight - scroller.clientHeight;
        if (target <= maxScroll) {
            scroller.scrollTop = target;
            return;
        }
        this.fillerPx += target - maxScroll;
        this.pendingScrollTop = target;
    }

    handleScroll(event) {
        if (this.fillerPx === 0) return;
        const { scrollTop, clientHeight, scrollHeight } = event.target;
        const fillerOutOfView = scrollTop + clientHeight <= scrollHeight - this.fillerPx;
        if (fillerOutOfView) this.fillerPx = 0;
    }

    nextPage() {
        if (this.isLastPage) return;
        this.goToPage(this.pageIndex + 1);
    }

    firstPage() {
        if (this.isFirstPage) return;
        this.goToPage(0);
    }

    lastPage() {
        if (this.isLastPage) return;
        this.goToPage(Math.ceil(this.totalChains / this.pageSize) - 1);
    }

    previousPage() {
        if (this.isFirstPage) return;
        this.goToPage(this.pageIndex - 1);
    }

    goToPage(index) {
        const block = Math.floor((index * this.pageSize) / PREFETCH_CHAINS);
        if (block !== this.blockIndex) this.holdListUntilLoaded();
        this.pageIndex = index;
        if (block !== this.blockIndex) {
            this.blockIndex = block;
            this.reload({ silent: true });
        }
    }

    selectRange(event) {
        this.holdListUntilLoaded();
        this.rangeOverride = Number(event.detail.value);
        this.allChainsBlock = null;
        this.watchedChainIds = new Set();
        this.pageIndex = 0;
        this.blockIndex = 0;
        this.reload({ silent: true });
    }

    selectFilter(event) {
        const filter = event.currentTarget.dataset.filter;
        if (filter === this.filter) return;
        if (!this.holdsEveryChain) this.holdListUntilLoaded();
        this.filter = filter;
        this.watchedChainIds = new Set();
        this.pageIndex = 0;
        this.blockIndex = 0;
        if (this.holdsEveryChain) this.showFilteredFromMemory();
        this.reload({ silent: true });
    }

    toggleLegend() {
        if (this.showLegend) {
            this.closeLegend();
            return;
        }
        this.showLegend = true;
        this.focusLegendClose = true;
        document.addEventListener('keydown', this.closeLegendOnEscape);
    }

    closeLegend() {
        this.showLegend = false;
        document.removeEventListener('keydown', this.closeLegendOnEscape);
    }

    closeLegendOnClickBeside(event) {
        if (this.showLegend && !this.refs.legend.contains(event.target)) this.closeLegend();
    }

    async handleRequeue(event) {
        const { resultIds, label } = event.detail;
        const confirmed = await LightningConfirm.open({
            label: 'Requeue',
            message: `Requeue ${label}? The replay runs as a new sequence; the failed result stays as it is.`,
            theme: 'warning',
            variant: 'header'
        });
        if (!confirmed) return;
        try {
            const outcome = await requeue({ resultIds });
            const count = outcome.requeued.length;
            const skipped = Object.values(outcome.skipReasonByResultId || {});
            const dropped = Object.values(outcome.droppedDependencyByResultId || {});
            const notes = [...skipped, ...dropped];
            this.dispatchEvent(
                new ShowToastEvent({
                    title: `${count} step${count === 1 ? '' : 's'} requeued`,
                    message: notes.length
                        ? notes.join(' ')
                        : 'The replay runs as a new sequence at the top of this list.',
                    variant: skipped.length ? 'warning' : 'success',
                    mode: notes.length ? 'sticky' : 'dismissible'
                })
            );
        } catch (failure) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Requeue failed',
                    message: failure?.body?.message || failure?.message || String(failure),
                    variant: 'error',
                    mode: 'sticky'
                })
            );
        }
        this.pollStartedAt = Date.now();
        this.replayGraceUntil = Date.now() + POLL.graceAfterRequeue;
        this.pollFailures = 0;
        this.stopped = false;
        this.pageIndex = 0;
        this.blockIndex = 0;
        await this.reload({ silent: true });
        this.schedulePoll(POLL.afterRequeue);
    }

    handleOpenReplay(event) {
        const { resultId, chainId } = event.detail;
        const loaded = (this.page?.sequences || []).findIndex(
            sequence => sequence.chainId === chainId
        );
        if (loaded < 0) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: { recordId: resultId, actionName: 'view' }
            });
            return;
        }
        this.pageIndex = Math.floor((this.blockIndex * PREFETCH_CHAINS + loaded) / this.pageSize);
        Promise.resolve().then(() => {
            const card = [...this.template.querySelectorAll('c-async-job-sequence')].find(
                candidate => candidate.sequence?.chainId === chainId
            );
            if (!card) return;
            this.rememberOpen(chainId, true);
            card.expand();
            card.scrollTo();
        });
    }

    handleOpenMap(event) {
        const sequence = this.page.sequences.find(
            candidate => candidate.chainId === event.detail.chainId
        );
        AsyncChainMap.open({
            sequence,
            size: 'large',
            label: `Chain map · ${sequence.name || 'Async jobs'}`
        });
    }

    handleOpenResult(event) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: event.detail.resultId, actionName: 'view' }
        });
    }

    viewAllResults() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: { objectApiName: ASYNC_RESULT.objectApiName, actionName: 'list' },
            state: { filterName: NAMESPACE_PREFIX + 'ByChain' }
        });
    }
}
