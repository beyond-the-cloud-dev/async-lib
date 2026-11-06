import USER_LOCALE from '@salesforce/i18n/locale';
import { LightningElement, api } from 'lwc';
import {
    CAPS,
    tagsFor,
    failedPageGroups,
    formatDuration,
    pageStripFor,
    delayOf,
    chunkRunAlive,
    recordsOf,
    truncate,
    sameData,
    pageStripStyle,
    SOURCE_SALESFORCE
} from 'c/asyncJobTimelineModel';

const GLYPHS = { ok: '✓', bad: '✕', skip: '→', wait: '○', delay: '◷', run: '', retry: '↻' };
const EXPLAINED_STATUSES = new Set(['FAILED', 'FRAMEWORK_ERROR', 'SKIPPED_DEPENDENCY']);
const PLATFORM_LABELS = {
    Queued: 'waiting in the queue',
    Holding: 'holding in the flex queue',
    Preparing: 'on the platform',
    Processing: 'on the platform',
    Completed: 'result pending · the finalizer writes it',
    Aborted: 'aborted on the platform',
    Failed: 'failed on the platform'
};
const OUTCOME_WORDS = { SUCCESS: 'succeeded', FAILURE: 'failed', COMPLETED: 'finished' };

const chipOf = record => {
    const inSalesforce = record.source === SOURCE_SALESFORCE;
    const elsewhere = [record.source, record.objectName].filter(Boolean).join(' ');
    return {
        key: `${record.source || ''}|${record.key}`,
        label: inSalesforce
            ? record.name
            : [record.objectName, record.key].filter(Boolean).join(' '),
        url: inSalesforce ? '/' + record.key : null,
        title: inSalesforce
            ? `${record.objectName || 'Record'} · opens in a new tab`
            : elsewhere || 'Record in another system'
    };
};

export default class AsyncJobStep extends LightningElement {
    @api canRequeue = false;
    @api chainInFlight = false;
    @api isNew = false;
    @api isChanged = false;
    @api isCurrent = false;
    @api isTarget = false;
    @api isLastRow = false;
    @api pageRecordId;

    @api
    get row() {
        return this.knownRow;
    }
    set row(value) {
        if (!sameData(value, this.knownRow)) this.knownRow = value;
    }

    @api
    get nameByCustomJobId() {
        return this.knownNames;
    }
    set nameByCustomJobId(value) {
        if (!sameData(value, this.knownNames)) this.knownNames = value;
    }

    knownRow;
    knownNames = {};
    expanded = false;
    showFullException = false;
    showAllChips = false;

    get step() {
        return this.row.step;
    }

    get status() {
        return this.row.status;
    }

    get rowClass() {
        return {
            step: true,
            'is-sub': this.row.depth > 0,
            'is-new': this.isNew,
            'is-changed': this.isChanged,
            'is-current': this.isCurrent,
            'is-target': this.isTarget,
            'is-last-row': this.isLastRow
        };
    }

    get glyphClass() {
        return `glyph glyph-${this.status.key}`;
    }

    get glyphText() {
        return GLYPHS[this.status.key];
    }

    get statusClass() {
        return `status status-${this.status.key}`;
    }

    get displayName() {
        return this.step.jobName || this.step.className;
    }

    get nameTitle() {
        return this.step.jobName ? this.step.className : this.displayName;
    }

    get allTags() {
        return tagsFor(this.row, this.nameByCustomJobId);
    }

    get tags() {
        return this.allTags.slice(0, CAPS.tags).map(tag => ({
            ...tag,
            className: tag.targetJobId ? 'tag tag-pointer' : 'tag',
            tabIndex: tag.targetJobId ? 0 : null
        }));
    }

    get hiddenTags() {
        return this.allTags.slice(CAPS.tags).map(tag => tag.label);
    }

    get hiddenTagLabel() {
        return this.hiddenTags.length ? `+${this.hiddenTags.length}` : null;
    }

    get hiddenTagTitle() {
        return this.hiddenTags.join(' · ');
    }

    showTagTarget(event) {
        const jobId = event.currentTarget.dataset.target;
        if (jobId) this.dispatchEvent(new CustomEvent('tagtarget', { detail: { jobId } }));
    }

    clearTagTarget(event) {
        if (!event.currentTarget.dataset.target) return;
        this.dispatchEvent(new CustomEvent('tagtarget', { detail: { jobId: null } }));
    }

    get timedSteps() {
        return this.row.kind === 'chunk' ? this.row.pages : [this.step];
    }

    get startedAtMs() {
        const starts = this.timedSteps
            .map(page => Date.parse(page.startedAt))
            .filter(Number.isFinite);
        return starts.length === 0 ? null : Math.min(...starts);
    }

    get finishedAtMs() {
        const ends = this.timedSteps
            .map(page => Date.parse(page.finishedAt))
            .filter(Number.isFinite);
        return ends.length === 0 ? null : Math.max(...ends);
    }

    get durationMs() {
        if (this.startedAtMs === null || this.finishedAtMs === null) return null;
        return this.finishedAtMs - this.startedAtMs;
    }

    get runStillGoing() {
        return this.row.kind === 'chunk' && chunkRunAlive(this.row);
    }

    get duration() {
        return formatDuration(this.durationMs);
    }

    get platformLabel() {
        if (this.status.key === 'delay') return null;
        if (this.step.status !== 'ENQUEUED' || !this.step.apexJobStatus) return null;
        return PLATFORM_LABELS[this.step.apexJobStatus] || this.step.apexJobStatus;
    }

    get platformTitle() {
        return `Salesforce job ${this.step.salesforceJobId || ''} · ${this.step.apexJobStatus}`;
    }

    get attemptLabel() {
        if (!this.step.retryAttempts) return null;
        return `attempt ${this.step.retryAttempts + 1}`;
    }

    get delayUntil() {
        return delayOf(this.row).until;
    }

    get plannedDelayLabel() {
        const { plannedMinutes } = delayOf(this.row);
        return plannedMinutes ? `delay ${plannedMinutes} min` : null;
    }

    get nextAttemptAt() {
        return this.status.key === 'retry' ? this.step.nextAttemptAt : null;
    }

    get isExplained() {
        return EXPLAINED_STATUSES.has(this.step.status);
    }

    get expandLabel() {
        return this.expanded ? 'Hide details' : 'Details';
    }

    get expandIcon() {
        return this.expanded ? 'utility:chevronup' : 'utility:chevrondown';
    }

    get exceptionText() {
        const message = this.step.exceptionMessage || '';
        return this.showFullException ? message : truncate(message, CAPS.exceptionChars);
    }

    get hasMoreException() {
        return (
            !this.showFullException &&
            (this.step.exceptionMessage || '').length > CAPS.exceptionChars
        );
    }

    get retryLines() {
        return (this.step.retryHistory || '').split('\n').filter(Boolean);
    }

    get showOwnException() {
        return !this.isChunk && Boolean(this.step.exceptionType || this.step.exceptionMessage);
    }

    get showFailure() {
        return Boolean(
            this.showOwnException || this.step.skipReason || this.failedPages.groups.length
        );
    }

    get isOutcomeRow() {
        return ['bad', 'skip'].includes(this.status.key) && this.row.kind !== 'chunk';
    }

    get requeueable() {
        return (
            this.canRequeue &&
            !this.chainInFlight &&
            this.isOutcomeRow &&
            this.step.requeueStatus === 'Stored'
        );
    }

    get warning() {
        if (!this.isOutcomeRow || !this.isExplained) return null;
        if (['Stored', 'Requeued'].includes(this.step.requeueStatus)) return null;
        return this.step.requeueStatus
            ? `Cannot be requeued: ${this.step.requeueStatus}. Enqueue it fresh from code.`
            : 'Cannot be requeued: payload not stored (StoreJobPayload is not Yes). Enqueue it fresh from code.';
    }

    get skipReasonVisible() {
        return this.status.key === 'skip' && this.step.skipReason && !this.expanded;
    }

    get resultUrl() {
        return '/' + this.step.id;
    }

    get linkedElsewhere() {
        return recordsOf(this.row).filter(record => record.key !== this.pageRecordId);
    }

    get chips() {
        const records = this.linkedElsewhere;
        const shown = this.showAllChips
            ? records.slice(0, CAPS.chipsExpanded)
            : records.slice(0, CAPS.chips);
        return shown.map(chipOf);
    }

    get replayLink() {
        return this.step.requeueStatus === 'Requeued' && this.step.replayResultId
            ? { resultId: this.step.replayResultId, chainId: this.step.replayChainId }
            : null;
    }

    get hiddenChipCount() {
        return this.showAllChips ? 0 : Math.max(this.linkedElsewhere.length - CAPS.chips, 0);
    }

    get hiddenChipLabel() {
        return `+${this.hiddenChipCount}`;
    }

    get strip() {
        return this.row.kind === 'chunk' ? pageStripFor(this.row) : null;
    }

    get squares() {
        return (this.strip?.squares || []).map(square => ({
            key: square.page,
            className: `sq sq-${square.key}`,
            title: `page ${square.page}`
        }));
    }

    get stripBarStyle() {
        return pageStripStyle(this.row);
    }

    get isChunk() {
        return this.row.kind === 'chunk';
    }

    get failedPages() {
        return this.isChunk ? failedPageGroups(this.row) : { groups: [], moreFailed: 0 };
    }

    get failedGroups() {
        return this.failedPages.groups.map(group => ({
            key: group.key,
            exceptionType: group.exceptionType,
            message: truncate(group.message, CAPS.exceptionChars),
            title: `${group.pages.length > 1 ? 'Pages' : 'Page'} ${group.pages
                .map(page => page.chunkPage)
                .join(', ')} failed`,
            links: group.pages.map(page => ({
                key: page.id,
                label: page.name,
                url: '/' + page.id
            }))
        }));
    }

    get failedMoreLabel() {
        const { moreFailed } = this.failedPages;
        return moreFailed ? `and ${moreFailed} more failed` : null;
    }

    get resultLinkLabel() {
        return `${this.isChunk ? 'Open first page result' : 'Open result'} ${this.step.name}`;
    }

    get facts() {
        const step = this.step;
        const names = this.nameByCustomJobId;
        const dependencies = this.dependencies
            .map(
                dependency =>
                    `after ${names[dependency.resolvedTargetCustomJobId] || 'an earlier job'} ${OUTCOME_WORDS[dependency.requiredOutcome] || 'finished'}`
            )
            .join(', ');
        const records = recordsOf(this.row).length;
        return [
            ['Class', step.className, 'class', 'mono'],
            ['Custom job id', step.customJobId, 'custom-job-id', 'mono'],
            ['Salesforce job', step.salesforceJobId, 'salesforce-job-id', 'mono'],
            ['Position', step.chainSequence ? `#${step.chainSequence}` : null],
            [
                'Priority',
                step.priority !== null && step.priority !== undefined ? step.priority : null
            ],
            [
                'Pages',
                this.row.kind === 'chunk'
                    ? `${this.row.pages.length} of ${step.chunkPages || this.row.pages.length}`
                    : null
            ],
            ['Attempts', step.retryAttempts ? step.retryAttempts + 1 : null],
            ['Started', this.formatted(this.startedAtMs)],
            ['Finished', this.runStillGoing ? null : this.formatted(this.finishedAtMs)],
            ['Duration', this.duration],
            ['Delay', step.delayMinutes ? `${step.delayMinutes} min` : null],
            ['Next attempt', this.formatted(step.nextAttemptAt)],
            ['Depends on', dependencies || null],
            ['Requeue', step.requeueStatus],
            ['Records', records ? `${records} linked` : null]
        ]
            .filter(([, value]) => value !== null && value !== undefined && value !== '')
            .map(([label, value, id, className]) => ({
                label,
                value: String(value),
                id: id || label.toLowerCase().replace(/\s+/g, '-'),
                className: className || ''
            }));
    }

    get dependencies() {
        if (!this.step.dependencies) return [];
        try {
            const parsed = JSON.parse(this.step.dependencies);
            return Array.isArray(parsed) ? parsed : [];
        } catch {
            return [];
        }
    }

    formatted(moment) {
        const at = new Date(moment);
        if (!moment || Number.isNaN(at.getTime())) return null;
        return at.toLocaleString(USER_LOCALE, {
            day: 'numeric',
            month: 'short',
            hour: '2-digit',
            minute: '2-digit',
            second: '2-digit'
        });
    }

    toggleExpanded(event) {
        event?.stopPropagation();
        this.expanded = !this.expanded;
    }

    stopClick(event) {
        event.stopPropagation();
    }

    openReplay(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('openreplay', { detail: this.replayLink }));
    }

    showWholeException() {
        this.showFullException = true;
    }

    showAllRecords(event) {
        event?.stopPropagation();
        this.showAllChips = true;
    }

    handleRequeue() {
        this.dispatchEvent(
            new CustomEvent('requeue', {
                detail: { resultIds: [this.step.id], label: this.displayName }
            })
        );
    }
}
