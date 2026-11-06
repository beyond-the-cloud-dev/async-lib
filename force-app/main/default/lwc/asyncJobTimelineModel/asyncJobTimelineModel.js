import USER_LOCALE from '@salesforce/i18n/locale';

export const VERSION = '3.1.0';
export const SOURCE_SALESFORCE = 'Salesforce';

export const CAPS = {
    stepsCollapsed: 20,
    stepsMax: 200,
    pageSquares: 60,
    failedPagesListed: 10,
    tags: 2,
    chips: 3,
    dots: 16,
    dotsPerChunk: 3,
    chipsExpanded: 20,
    exceptionChars: 300,
    mapBoxes: 40,
    mapCollapseRun: 5
};

export const POLL = {
    running: 3000,
    queued: 10000,
    afterRequeue: 2000,
    graceAfterRequeue: 120000,
    maxSleep: 300000,
    staleMinutes: 10,
    maxMinutes: 30,
    maxFailures: 3
};

export const RANGES = [
    { days: 1, label: 'Last 24 hours' },
    { days: 7, label: 'Last 7 days' },
    { days: 30, label: 'Last 30 days' },
    { days: 0, label: 'All time' }
];

const SKIP_LABELS = {
    SKIPPED_DEPENDENCY: 'Skipped · dependency',
    SKIPPED_CHAIN_STOPPED: 'Skipped · chain stopped',
    SKIPPED_CHUNK_STOPPED: 'Skipped · chunk run stopped',
    SKIPPED_EXPLICIT: 'Skipped · by code',
    SKIPPED_DISABLED: 'Skipped · disabled'
};

const PLATFORM_RUNNING = new Set(['Processing', 'Preparing']);
// The platform reports Completed or Failed as soon as execute() returns; the finalizer that writes
// the row runs in its own transaction, often seconds later. The step is not queued any more, nor
// done. Aborted jobs get no finalizer, so that one is final.
const PLATFORM_FINISHING = new Set(['Completed', 'Failed']);
const PLATFORM_ENDED = { Aborted: 'Aborted' };
const OUTCOME_WORDS = { SUCCESS: 'succeeded', FAILURE: 'failed', COMPLETED: 'finished' };

export function statusOf(step) {
    if (step.status === 'COMPLETED') return { key: 'ok', label: 'Completed' };
    if (step.status === 'FAILED') return { key: 'bad', label: 'Failed' };
    if (step.status === 'FRAMEWORK_ERROR') return { key: 'bad', label: 'Framework error' };
    if (SKIP_LABELS[step.status]) return { key: 'skip', label: SKIP_LABELS[step.status] };
    if (step.status === 'ENQUEUED') return enqueuedStatusOf(step);
    return { key: 'wait', label: step.status || 'Unknown' };
}

const isWaitingOutDelay = step =>
    !step.retryAttempts && Date.parse(step.nextAttemptAt) > Date.now();

function enqueuedStatusOf(step) {
    if (step.nextAttemptAt && step.retryAttempts > 0) return { key: 'retry', label: 'Retrying' };
    if (PLATFORM_RUNNING.has(step.apexJobStatus)) return { key: 'run', label: 'Running' };
    if (PLATFORM_FINISHING.has(step.apexJobStatus)) return { key: 'run', label: 'Finishing' };
    if (PLATFORM_ENDED[step.apexJobStatus])
        return { key: 'bad', label: PLATFORM_ENDED[step.apexJobStatus] };
    if (isWaitingOutDelay(step)) return { key: 'delay', label: 'Delayed' };
    if (step.apexJobStatus) return { key: 'wait', label: 'Queued' };
    return { key: 'wait', label: 'Enqueued' };
}

const bySequence = (a, b) => {
    const seqA = a.chainSequence ?? Number.MAX_SAFE_INTEGER;
    const seqB = b.chainSequence ?? Number.MAX_SAFE_INTEGER;
    if (seqA !== seqB) return seqA - seqB;
    return String(a.createdAt || '').localeCompare(String(b.createdAt || ''));
};

const rowsBySteps = new WeakMap();

const delayHasEnded = row => row.status.key === 'delay' && delayOf(row).until === null;

export function groupSteps(steps) {
    if (!steps) return buildRows([]);
    const cached = rowsBySteps.get(steps);
    if (cached && !cached.some(delayHasEnded)) return cached;
    const rows = buildRows(steps);
    rowsBySteps.set(steps, rows);
    return rows;
}

function buildRows(steps) {
    const sorted = [...steps].sort(bySequence);
    const topLevel = [];
    const finalizersByParent = new Map();
    const chunkRows = new Map();
    sorted.forEach(step => {
        if (step.parentCustomJobId) {
            const siblings = finalizersByParent.get(step.parentCustomJobId) || [];
            siblings.push(step);
            finalizersByParent.set(step.parentCustomJobId, siblings);
            return;
        }
        if (step.chunkRunId) {
            const run = chunkRows.get(step.chunkRunId);
            if (run) {
                run.pages.push(step);
                return;
            }
            const row = { kind: 'chunk', step, pages: [step], depth: 0 };
            chunkRows.set(step.chunkRunId, row);
            topLevel.push(row);
            return;
        }
        topLevel.push({ kind: 'job', step, depth: 0 });
    });
    const known = new Set(topLevel.map(row => row.step.customJobId));
    const rows = [];
    topLevel.forEach(row => {
        rows.push(row);
        (finalizersByParent.get(row.step.customJobId) || []).forEach(finalizer => {
            rows.push({ kind: 'finalizer', step: finalizer, depth: 1 });
        });
    });
    finalizersByParent.forEach((orphans, parent) => {
        if (known.has(parent)) return;
        orphans.forEach(orphan => rows.push({ kind: 'finalizer', step: orphan, depth: 0 }));
    });
    return rows.map(row => ({
        ...row,
        key: row.step.customJobId || row.step.id,
        status: rowStatusOf(row)
    }));
}

const STATUS_BUCKET = {
    ok: 'completed',
    bad: 'failed',
    skip: 'skipped',
    wait: 'waiting',
    delay: 'waiting',
    run: 'running',
    retry: 'waiting'
};

const CHUNK_RUN_ENDED = new Set(['SKIPPED_CHUNK_STOPPED', 'FRAMEWORK_ERROR']);

const pagesStillComing = row =>
    row.kind === 'chunk' &&
    row.step.chunkPages > row.pages.length &&
    !row.pages.some(page => CHUNK_RUN_ENDED.has(page.status));

export const chunkRunAlive = row =>
    row.kind === 'chunk' &&
    (['run', 'wait', 'delay', 'retry'].includes(row.status.key) || pagesStillComing(row));

function rowStatusOf(row) {
    if (row.kind !== 'chunk') return statusOf(row.step);
    const statuses = row.pages.map(statusOf);
    const inFlight = statuses.find(status =>
        ['run', 'retry', 'wait', 'delay'].includes(status.key)
    );
    if (inFlight) return inFlight;
    const failed = statuses.filter(status => status.key === 'bad').length;
    if (failed > 0) return { key: 'bad', label: `${failed} page${failed === 1 ? '' : 's'} failed` };
    if (row.pages.some(page => page.status === 'SKIPPED_CHUNK_STOPPED')) {
        const lastDone = row.pages.filter(page => statusOf(page).key === 'ok').length;
        return { key: 'skip', label: `Stopped after page ${lastDone}` };
    }
    const skipped = statuses.find(status => status.key === 'skip');
    return skipped || { key: 'ok', label: 'Completed' };
}

export function expectedPagesOf(row) {
    return Math.max(row.step.chunkPages || 0, row.pages.length);
}

export function progressOf(rows) {
    const progress = {
        total: 0,
        completed: 0,
        failed: 0,
        skipped: 0,
        running: 0,
        waiting: 0,
        pending: 0,
        steps: 0,
        stepsCompleted: 0,
        pages: 0,
        pagesDone: 0
    };
    const steps = rows.filter(row => row.kind !== 'chunk');
    const byPages = steps.length === 0 || rows.some(chunkRunAlive);
    rows.forEach(row => {
        if (row.kind !== 'chunk' || !byPages) {
            progress.steps += 1;
            progress.total += 1;
            progress[STATUS_BUCKET[row.status.key]] += 1;
            if (row.status.key === 'ok') progress.stepsCompleted += 1;
            return;
        }
        if (steps.length > 0) {
            progress.steps += 1;
            if (row.status.key === 'ok') progress.stepsCompleted += 1;
        }
        const expected = expectedPagesOf(row);
        progress.pages += expected;
        progress.total += expected;
        row.pages.forEach(page => {
            const key = statusOf(page).key;
            progress[STATUS_BUCKET[key]] += 1;
            if (['ok', 'bad', 'skip'].includes(key)) progress.pagesDone += 1;
        });
        if (!row.pages.some(page => CHUNK_RUN_ENDED.has(page.status)))
            progress.pending += expected - row.pages.length;
    });
    progress.percent =
        progress.total === 0 ? 0 : Math.round((progress.completed / progress.total) * 100);
    return progress;
}

const HELD_BY_PLATFORM = row =>
    ['retry', 'delay'].includes(row.status.key) ||
    (row.status.key === 'wait' && row.status.label === 'Queued');

export function currentRowKey(rows) {
    const running = rows.find(row => row.status.key === 'run');
    const current = running || rows.find(HELD_BY_PLATFORM);
    return current ? current.key : null;
}

export const QUIET_RUN_MS = POLL.staleMinutes * 60 * 1000;

export function sequenceSummary(rows, now = Date.now()) {
    const summary = {
        total: rows.length,
        completed: 0,
        failed: 0,
        skipped: 0,
        waiting: 0,
        running: 0,
        failedSteps: 0,
        settledSteps: 0,
        delayedUntil: null
    };
    let earliest = null;
    let latest = null;
    let lastActivity = null;
    rows.forEach(row => {
        summary[STATUS_BUCKET[row.status.key]] += 1;
        const steps = row.kind === 'chunk' ? row.pages : [row.step];
        steps.forEach(step => {
            const key = statusOf(step).key;
            if (key === 'bad') summary.failedSteps += 1;
            if (key === 'delay') summary.delayedUntil = step.nextAttemptAt;
            if (['ok', 'bad', 'skip'].includes(key)) summary.settledSteps += 1;
            const started = Date.parse(step.startedAt || step.createdAt);
            const finished = Date.parse(step.finishedAt);
            if (!Number.isNaN(started))
                earliest = earliest === null ? started : Math.min(earliest, started);
            if (!Number.isNaN(finished))
                latest = latest === null ? finished : Math.max(latest, finished);
            lastActivity = Math.max(lastActivity ?? 0, started || 0, finished || 0) || null;
        });
    });
    summary.progress = progressOf(rows);
    summary.percent = summary.progress.percent;
    summary.activity = activityOf(rows);
    summary.status = overallStatus(summary, rows, lastActivity, now);
    summary.durationMs =
        earliest !== null && latest !== null && latest >= earliest ? latest - earliest : null;
    return summary;
}

function activityOf(rows) {
    if (rows.some(row => row.status.key === 'run')) return 'executing';
    if (rows.some(row => row.status.key === 'retry')) return 'retrying';
    return 'waiting';
}

function overallStatus(summary, rows, lastActivity, now) {
    if (summary.settledSteps === 0 && summary.activity !== 'executing')
        return summary.delayedUntil ? 'delayed' : 'queued';
    const quiet = lastActivity !== null && now - lastActivity > QUIET_RUN_MS;
    const inFlight = summary.running + summary.waiting > 0;
    if (inFlight || (rows.some(pagesStillComing) && !quiet)) return 'running';
    if (summary.failed > 0) return 'failed';
    if (rows.some(row => row.step.status === 'SKIPPED_CHAIN_STOPPED')) return 'stopped';
    return 'completed';
}

export function collapseCompletedRuns(rows, cap = CAPS.stepsCollapsed) {
    if (rows.length <= cap) return rows;
    const keep = rows.map(
        (row, index) => index < 3 || index >= rows.length - 2 || row.status.key !== 'ok'
    );
    const collapsed = [];
    let hidden = [];
    const flush = () => {
        if (hidden.length === 0) return;
        collapsed.push({
            kind: 'gap',
            key: 'gap-' + hidden[0].key,
            hiddenCount: hidden.length,
            hiddenRows: hidden
        });
        hidden = [];
    };
    rows.forEach((row, index) => {
        if (keep[index]) {
            flush();
            collapsed.push(row);
        } else {
            hidden.push(row);
        }
    });
    flush();
    return collapsed;
}

const statusSignature = row => row.status.key + '|' + row.status.label;

export function diffRows(previousRows, nextRows) {
    const added = new Set();
    const changed = new Set();
    if (!previousRows) return { added, changed };
    const previousByKey = new Map(previousRows.map(row => [row.key, statusSignature(row)]));
    nextRows.forEach(row => {
        if (!previousByKey.has(row.key)) added.add(row.key);
        else if (previousByKey.get(row.key) !== statusSignature(row)) changed.add(row.key);
    });
    return { added, changed };
}

export function formatDuration(ms) {
    if (ms === null || ms === undefined || Number.isNaN(ms) || ms < 0) return null;
    if (ms < 100) return '<0.1 s';
    if (ms < 1000) return (ms / 1000).toFixed(1) + ' s';
    if (ms < 60000) return Math.round(ms / 1000) + ' s';
    const totalSeconds = Math.round(ms / 1000);
    const hours = Math.floor(totalSeconds / 3600);
    const minutes = Math.floor((totalSeconds % 3600) / 60);
    const seconds = totalSeconds % 60;
    if (hours > 0) return `${hours} h ${minutes} min`;
    return `${minutes} min ${seconds} s`;
}

const MINUTE = 60000;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;
const timeOf = date => date.toLocaleTimeString(USER_LOCALE, { hour: '2-digit', minute: '2-digit' });

export function relativeTime(iso, now = Date.now()) {
    const at = Date.parse(iso);
    if (!iso || Number.isNaN(at)) return null;
    const date = new Date(at);
    const full = date.toLocaleString(USER_LOCALE, {
        day: 'numeric',
        month: 'short',
        year: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit'
    });
    const age = now - at;
    let text;
    if (age < MINUTE) text = 'just now';
    else if (age < HOUR) text = `${Math.floor(age / MINUTE)} min ago`;
    else if (age < DAY) {
        const hours = Math.floor(age / HOUR);
        const minutes = Math.floor((age % HOUR) / MINUTE);
        text = minutes ? `${hours} h ${minutes} min ago` : `${hours} h ago`;
    } else if (age < 2 * DAY) text = `Yesterday, ${timeOf(date)}`;
    else if (age < 7 * DAY)
        text = `${date.toLocaleDateString(USER_LOCALE, { weekday: 'short' })}, ${timeOf(date)}`;
    else
        text = date.toLocaleString(USER_LOCALE, {
            day: 'numeric',
            month: 'short',
            year: 'numeric',
            hour: '2-digit',
            minute: '2-digit'
        });
    return { text, full };
}

export function recordsOf(row) {
    const steps = row.kind === 'chunk' ? row.pages : [row.step];
    const seen = new Set();
    const records = [];
    steps.forEach(step => {
        (step.records || []).forEach(record => {
            const identity = `${record.source || ''}|${record.key}`;
            if (seen.has(identity)) return;
            seen.add(identity);
            records.push(record);
        });
    });
    return records;
}

export function tagsFor(row, nameByCustomJobId = {}) {
    const step = row.step;
    const nameOf = customJobId => nameByCustomJobId[customJobId] || 'an earlier job';
    const tags = [];
    const addTag = (label, targetJobId) => tags.push({ label, targetJobId });
    if (row.kind === 'finalizer' && step.parentCustomJobId)
        addTag('finalizer of ' + nameOf(step.parentCustomJobId), step.parentCustomJobId);
    if (step.addedByCustomJobId)
        addTag('↳ added by ' + nameOf(step.addedByCustomJobId), step.addedByCustomJobId);
    if (row.kind === 'chunk') addTag(chunkTagOf(row));
    parsedDependencies(step).forEach(dependency => {
        const target = dependency.resolvedTargetCustomJobId;
        addTag(
            `after ${nameOf(target)} ${OUTCOME_WORDS[dependency.requiredOutcome] || 'finished'}`,
            target
        );
    });
    if (step.priority !== null && step.priority !== undefined) addTag('P' + step.priority);
    const settledBadly = ['bad', 'skip'].includes(row.status.key);
    if (settledBadly && step.requeueStatus === 'Requeued') addTag('requeued');
    else if (settledBadly && step.requeueStatus !== 'Stored') addTag('not requeueable');
    return tags;
}

export function rowKeyOf(rows, customJobId) {
    if (!customJobId) return null;
    const owner = rows.find(
        row => row.key === customJobId || row.pages?.some(page => page.customJobId === customJobId)
    );
    return owner?.key ?? null;
}

export function dotsFit(rows) {
    if (rows.every(row => row.kind === 'chunk')) return false;
    const needed = rows.reduce(
        (sum, row) => sum + (row.kind === 'chunk' ? CAPS.dotsPerChunk : 1),
        0
    );
    return needed <= CAPS.dots;
}

export function pluralOf(count, word) {
    return `${count} ${word}${count === 1 ? '' : 's'}`;
}

function chunkTagOf(row) {
    return `chunk · ${pluralOf(expectedPagesOf(row), 'page')}`;
}

function parsedDependencies(step) {
    if (!step.dependencies) return [];
    try {
        const parsed = JSON.parse(step.dependencies);
        return Array.isArray(parsed) ? parsed : [];
    } catch {
        return [];
    }
}

export function nextPollDelay(summary) {
    if (summary.status === 'running') return POLL.running;
    if (['queued', 'delayed'].includes(summary.status)) return POLL.queued;
    return null;
}

export function pollDelayFor(rows, now = Date.now()) {
    const inFlight = rows
        .flatMap(row => (row.kind === 'chunk' ? row.pages : [row.step]))
        .map(step => ({ step, status: statusOf(step) }))
        .filter(({ status }) => ['run', 'wait', 'delay', 'retry'].includes(status.key));
    if (inFlight.length === 0) return null;
    if (inFlight.some(({ status }) => status.key === 'run')) return POLL.running;
    if (inFlight.some(({ status }) => status.key === 'wait')) return POLL.queued;
    const dueIn = Math.min(...inFlight.map(({ step }) => Date.parse(step.nextAttemptAt) - now));
    if (Number.isNaN(dueIn) || dueIn <= POLL.queued) return POLL.queued;
    return Math.min(dueIn, POLL.maxSleep);
}

export function delayOf(row) {
    const steps = row.kind === 'chunk' ? row.pages : [row.step];
    const delayed = steps.find(step => statusOf(step).key === 'delay');
    const waitingForItsTurn = row.status.key === 'wait' && row.status.label === 'Enqueued';
    return {
        until: delayed?.nextAttemptAt ?? null,
        plannedMinutes: !delayed && waitingForItsTurn ? (row.step.delayMinutes ?? null) : null
    };
}

export function clockOf(iso) {
    return new Date(iso).toLocaleTimeString(USER_LOCALE, { hour: '2-digit', minute: '2-digit' });
}

function squaresFor(statuses, total) {
    const statusByPage = new Map(statuses.map(status => [status.page, status]));
    return Array.from({ length: total }, (_, index) => ({
        page: index + 1,
        key: statusByPage.get(index + 1)?.key || 'todo'
    }));
}

export function pageStripFor(row) {
    const pages = [...row.pages].sort((a, b) => (a.chunkPage || 0) - (b.chunkPage || 0));
    const total = expectedPagesOf(row);
    const statuses = pages.map(page => ({ page: page.chunkPage, key: statusOf(page).key }));
    const failedCount = statuses.filter(status => status.key === 'bad').length;
    const done = statuses.filter(status => ['ok', 'bad', 'skip'].includes(status.key)).length;
    const current = statuses.find(status => ['run', 'retry'].includes(status.key));
    const summary =
        (current ? `page ${current.page} of ${total}` : `${done} of ${pluralOf(total, 'page')}`) +
        (failedCount ? ` · ${failedCount} failed` : '');
    return {
        squares: total <= CAPS.pageSquares ? squaresFor(statuses, total) : null,
        summary,
        percent: total === 0 ? 0 : Math.round((done / total) * 100)
    };
}

export function failedPageGroups(row) {
    const failed = row.pages
        .filter(page => statusOf(page).key === 'bad')
        .sort((a, b) => (a.chunkPage || 0) - (b.chunkPage || 0));
    const groups = new Map();
    failed.slice(0, CAPS.failedPagesListed).forEach(page => {
        const key = `${page.exceptionType || ''}|${page.exceptionMessage || ''}`;
        if (!groups.has(key))
            groups.set(key, {
                key,
                exceptionType: page.exceptionType,
                message: page.exceptionMessage,
                pages: []
            });
        groups.get(key).pages.push(page);
    });
    return {
        groups: [...groups.values()],
        moreFailed: Math.max(failed.length - CAPS.failedPagesListed, 0)
    };
}

export function truncate(text, cap) {
    if (!text) return '';
    return text.length <= cap ? text : text.slice(0, cap) + '…';
}

export function sameData(a, b) {
    return JSON.stringify(a) === JSON.stringify(b);
}

const STRIP_COLORS = { ok: 'var(--ok)', bad: 'var(--bad)', skip: 'var(--warn)', run: 'var(--run)' };
const STRIP_MIN_PERCENT = 3;

export function pageStripStyle(row) {
    const total = expectedPagesOf(row);
    const counts = { ok: 0, bad: 0, skip: 0, run: 0 };
    row.pages.forEach(page => {
        const key = statusOf(page).key;
        counts[key in counts ? key : 'run'] += 1;
    });
    const widths = Object.fromEntries(
        Object.keys(counts).map(key => {
            const share = total === 0 ? 0 : (counts[key] / total) * 100;
            const floor = key === 'bad' || key === 'skip' ? STRIP_MIN_PERCENT : 0;
            return [key, counts[key] ? Math.max(share, floor) : 0];
        })
    );
    const spill = Math.max(0, widths.ok + widths.bad + widths.skip + widths.run - 100);
    widths.ok = Math.max(0, widths.ok - spill);
    const stops = [];
    let at = 0;
    Object.keys(widths).forEach(key => {
        if (!widths[key]) return;
        const to = at + widths[key];
        stops.push(`${STRIP_COLORS[key]} ${at.toFixed(1)}% ${to.toFixed(1)}%`);
        at = to;
    });
    stops.push(`var(--line) ${at.toFixed(1)}% 100%`);
    return `background:linear-gradient(to right, ${stops.join(', ')})`;
}
