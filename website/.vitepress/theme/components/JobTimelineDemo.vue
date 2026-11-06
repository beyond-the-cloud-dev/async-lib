<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { withBase } from 'vitepress';

const PAGES = 8;
const PAGE_MS = 600;
const CHUNK_START_MS = 2400;
const CHUNK_END_MS = CHUNK_START_MS + PAGE_MS * PAGES;
const ADDED_JOB_END_MS = CHUNK_END_MS + 2200;
const CHAIN_END_MS = ADDED_JOB_END_MS + 2200;
const HAND_OVER_MS = CHAIN_END_MS + 4000;
const STILL_FRAME_MS = CHUNK_START_MS + PAGE_MS * 5;

const STATUS_LABELS = { ok: 'Completed', run: 'Running', wait: 'Enqueued' };

const RUNS = [
    {
        name: 'Order approval pipeline',
        first: 'Validate order',
        second: 'Credit check',
        third: 'Reserve stock',
        chunk: 'Tax 16 lines',
        added: 'Notify sales team',
        last: 'Sync to ERP'
    },
    {
        name: 'Nightly stock sync',
        first: 'Read warehouse feed',
        second: 'Match SKUs',
        third: 'Adjust reservations',
        chunk: 'Update 16 locations',
        added: 'Alert buyers',
        last: 'Publish to storefront'
    },
    {
        name: 'Invoice export',
        first: 'Collect invoices',
        second: 'Apply tax rules',
        third: 'Render PDFs',
        chunk: 'Send 16 invoices',
        added: 'Flag late payers',
        last: 'Post to ledger'
    }
];

const runningChain = run => ({
    name: run.name,
    addedJobName: run.added,
    open: false,
    isNew: false,
    finished: false,
    age: 'just now',
    seconds: 12,
    pagesDone: 0,
    steps: [
        { id: 'first', name: run.first, status: 'ok', meta: '4 s' },
        { id: 'second', name: run.second, status: 'ok', meta: '6 s' },
        { id: 'third', name: run.third, status: 'run', meta: 'on the platform' },
        { id: 'chunk', name: run.chunk, status: 'wait', chunk: true },
        { id: 'last', name: run.last, status: 'wait' }
    ]
});

const finishedChain = (run, age) => {
    const chain = runningChain(run);
    chain.steps.forEach(step => (step.status = 'ok'));
    return { ...chain, age, finished: true, seconds: 21, pagesDone: PAGES };
};

const openChain = chain => ({ ...chain, open: true });

const chains = ref([openChain(runningChain(RUNS[0])), finishedChain(RUNS[2], '1 min ago')]);
const runIndex = ref(0);
const completedCount = ref(1);
const timers = [];

const currentChain = () => chains.value.find(chain => chain.open);
const stepOf = (chain, id) => chain.steps.find(step => step.id === id);

function setStep(id, status, meta) {
    Object.assign(stepOf(currentChain(), id), { status, meta });
}

function finishPage() {
    currentChain().pagesDone += 1;
}

function startChunk() {
    setStep('third', 'ok', '5 s');
    setStep('chunk', 'run');
    currentChain().seconds += 2;
}

function addJobAfterChunk() {
    const chain = currentChain();
    setStep('chunk', 'ok', '4 s');
    chain.steps.splice(4, 0, {
        id: 'added',
        name: chain.addedJobName,
        status: 'run',
        isNew: true,
        tag: `↳ added by ${stepOf(chain, 'chunk').name}`,
        meta: 'on the platform'
    });
    chain.seconds += 4;
}

function runLastStep() {
    setStep('added', 'ok', '1 s');
    setStep('last', 'run', 'on the platform');
    currentChain().seconds += 2;
    const nextRun = RUNS[(runIndex.value + 1) % RUNS.length];
    chains.value.unshift({ ...runningChain(nextRun), isNew: true });
}

function finishChain() {
    setStep('last', 'ok', '2 s');
    currentChain().finished = true;
    completedCount.value += 1;
}

function handOverToNextChain() {
    const finished = currentChain();
    const next = chains.value[0];
    finished.open = false;
    next.open = true;
    next.isNew = false;
    chains.value = [next, finished];
    runIndex.value = (runIndex.value + 1) % RUNS.length;
    schedule();
}

const beats = () => [
    [CHUNK_START_MS, startChunk],
    ...Array.from({ length: PAGES }, (_, page) => [
        CHUNK_START_MS + PAGE_MS * (page + 1),
        finishPage
    ]),
    [CHUNK_END_MS, addJobAfterChunk],
    [ADDED_JOB_END_MS, runLastStep],
    [CHAIN_END_MS, finishChain]
];

function schedule() {
    timers.length = 0;
    beats().forEach(([at, beat]) => timers.push(setTimeout(beat, at)));
    timers.push(setTimeout(handOverToNextChain, HAND_OVER_MS));
}

onMounted(() => {
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
        beats()
            .filter(([at]) => at <= STILL_FRAME_MS)
            .forEach(([, beat]) => beat());
        return;
    }
    schedule();
});

onBeforeUnmount(() => timers.forEach(clearTimeout));

const inFlight = computed(() => chains.value.filter(chain => !chain.finished).length);

const chips = computed(() => [
    { label: 'All', count: inFlight.value + completedCount.value + 1, active: true },
    { label: 'In flight', count: inFlight.value, live: true },
    { label: 'Failed', count: 1 },
    { label: 'Completed', count: completedCount.value }
]);

const stepsDoneOf = chain => chain.steps.filter(step => step.status === 'ok').length;

function percentOf(chain) {
    const jobs = chain.steps.filter(step => !step.chunk);
    const jobsDone = jobs.filter(step => step.status === 'ok').length;
    return Math.round(((jobsDone + chain.pagesDone) / (jobs.length + PAGES)) * 100);
}

const progressTextOf = chain =>
    `${stepsDoneOf(chain)} of ${chain.steps.length} steps completed · ` +
    `${chain.pagesDone} of ${PAGES} pages`;

function metaOf(chain) {
    const steps = `${chain.steps.length} steps · ${PAGES} pages`;
    return chain.finished
        ? `${chain.age} · ${chain.seconds} s · ${steps}`
        : `${chain.age} · running ${chain.seconds} s · ${steps}`;
}

const squaresOf = chain =>
    Array.from({ length: PAGES }, (_, page) => {
        if (page < chain.pagesDone) return 'ok';
        return page === chain.pagesDone && stepOf(chain, 'chunk').status === 'run' ? 'run' : 'todo';
    });

const pageSummaryOf = chain =>
    stepOf(chain, 'chunk').status === 'run'
        ? `page ${Math.min(chain.pagesDone + 1, PAGES)} of ${PAGES}`
        : `${chain.pagesDone} of ${PAGES} pages`;
</script>

<template>
    <a
        class="demo"
        :href="withBase('/features/job-timeline')"
        aria-label="See the Job Timeline. The Async Jobs card on a Salesforce record page. A chain of jobs runs step by step, a chunk run fills page by page, a job added at runtime appears in its place, and a new chain arrives on top."
    >
        <div class="card" aria-hidden="true">
            <div class="head">
                <img class="logo" :src="withBase('/logo.png')" alt="" />
                <span class="title">Async Jobs</span>
                <span class="live"><i></i>Live</span>
            </div>
            <div class="chips">
                <span
                    v-for="chip in chips"
                    :key="chip.label"
                    class="chip"
                    :class="{ active: chip.active, 'chip-live': chip.live && inFlight > 0 }"
                >
                    <i v-if="chip.live && inFlight > 0" class="chip-dot"></i>
                    {{ chip.label }} <b>{{ chip.count }}</b>
                </span>
            </div>

            <div class="list">
                <TransitionGroup name="arrive" tag="div">
                    <div v-for="chain in chains" :key="chain.name" class="chain">
                        <div class="chain-row" :class="{ open: chain.open }">
                            <span class="chevron" :class="{ down: chain.open }">›</span>
                            <div class="chain-text">
                                <div>
                                    <span class="chain-name">{{ chain.name }}</span>
                                    <span v-if="chain.finished" class="badge badge-ok">✓ Completed</span>
                                    <span v-else class="badge badge-run">Running</span>
                                    <span v-if="chain.isNew" class="badge badge-new">New</span>
                                </div>
                                <div class="chain-meta">
                                    <span v-if="chain.finished && !chain.open" class="dots">
                                        <i v-for="step in chain.steps" :key="step.id" class="ok"></i>
                                    </span>
                                    {{ metaOf(chain) }}
                                </div>
                            </div>
                        </div>

                        <div class="panel-slide" :class="{ open: chain.open }">
                            <div class="panel-clip">
                                <div class="panel">
                                    <div class="progress-text">
                                        <span>{{ progressTextOf(chain) }}</span>
                                        <span>{{ percentOf(chain) }} %</span>
                                    </div>
                                    <div class="bar"><i :style="{ width: percentOf(chain) + '%' }"></i></div>

                                    <TransitionGroup name="arrive" tag="div" class="steps">
                                        <div
                                            v-for="(step, index) in chain.steps"
                                            :key="step.id"
                                            class="step"
                                            :class="{
                                                current: step.status === 'run',
                                                added: step.isNew,
                                                last: index === chain.steps.length - 1
                                            }"
                                        >
                                            <span class="glyph" :class="'glyph-' + step.status">
                                                <template v-if="step.status === 'ok'">✓</template>
                                            </span>
                                            <div class="step-text">
                                                <div>
                                                    <span class="step-name">{{ step.name }}</span>
                                                    <span class="step-status" :class="'status-' + step.status">
                                                        {{ STATUS_LABELS[step.status] }}
                                                    </span>
                                                    <span v-if="step.isNew" class="badge badge-new">New</span>
                                                </div>
                                                <div v-if="step.chunk" class="step-meta">
                                                    <span class="strip">
                                                        <i
                                                            v-for="(square, page) in squaresOf(chain)"
                                                            :key="page"
                                                            :class="'sq-' + square"
                                                        ></i>
                                                    </span>
                                                    {{ pageSummaryOf(chain) }}
                                                </div>
                                                <div v-else-if="step.tag" class="step-meta">
                                                    <span class="tag">{{ step.tag }}</span>
                                                </div>
                                                <div v-else-if="step.meta" class="step-meta">{{ step.meta }}</div>
                                            </div>
                                        </div>
                                    </TransitionGroup>
                                </div>
                            </div>
                        </div>
                    </div>
                </TransitionGroup>

                <div class="chain-row">
                    <span class="chevron">›</span>
                    <div class="chain-text">
                        <div>
                            <span class="chain-name">Order fulfilment pipeline</span>
                            <span class="badge badge-bad">✕ Failed</span>
                        </div>
                        <div class="chain-meta">
                            <span class="dots">
                                <i class="ok"></i><i class="ok"></i><i class="bad"></i
                                ><i class="skip"></i><i class="skip"></i><i class="ok"></i>
                            </span>
                            3 min ago · 6 steps
                        </div>
                    </div>
                    <span class="requeue">↻ 3</span>
                </div>
            </div>

            <div class="foot">
                <span>Async Lib</span>
                <span>by Beyond The Cloud</span>
            </div>
        </div>
    </a>
</template>

<style scoped>
.demo {
    display: block;
    --ok: #2a7a44;
    --run: #016dc3;
    --bad: #ba0517;
    --skip: #dd7a01;
    --muted: #666;
    --line: #dfe3e8;
    position: relative;
    width: 100%;
    max-width: 500px;
    margin: 0 auto;
    color: #444;
    font-size: 13px;
    line-height: 1.35;
    text-align: left;
}
.card {
    display: flex;
    flex-direction: column;
    height: 520px;
    overflow: hidden;
    border: 1px solid var(--line);
    border-radius: 12px;
    background: #fff;
    box-shadow: 0 18px 50px rgba(0, 0, 0, 0.28);
    transition:
        transform 0.2s,
        box-shadow 0.2s;
}
.demo:hover .card {
    transform: translateY(-3px);
    box-shadow: 0 24px 60px rgba(0, 0, 0, 0.38);
}
.demo:focus-visible {
    border-radius: 12px;
    outline: 2px solid #0250d9;
    outline-offset: 4px;
}
.head {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 10px 14px;
}
.logo {
    width: 24px;
    height: 24px;
    border-radius: 4px;
}
.title {
    flex: 1;
    color: #032d60;
    font-size: 15px;
    font-weight: 700;
}
.live {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    color: var(--muted);
    font-size: 12px;
}
.live i {
    width: 7px;
    height: 7px;
    border-radius: 50%;
    background: var(--ok);
    animation: pulse 1.6s infinite;
}
.chips {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
    padding: 7px 14px;
    border-top: 1px solid var(--line);
    border-bottom: 1px solid var(--line);
    background: #fafafa;
}
.chip {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    padding: 1px 9px;
    border: 1px solid var(--line);
    border-radius: 999px;
    background: #fff;
    color: #2e2e2e;
    font-size: 12px;
}
.chip.active {
    border-color: var(--run);
    background: var(--run);
    color: #fff;
}
.chip-live {
    border-color: var(--run);
    color: var(--run);
    font-weight: 600;
}
.chip-dot {
    width: 7px;
    height: 7px;
    border-radius: 50%;
    background: var(--run);
    animation: pulse 1.6s infinite;
}
.list {
    flex: 1;
    overflow: hidden;
}
.chain-row {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 7px 14px 7px 12px;
    border-bottom: 1px solid var(--line);
}
.chain-row.open {
    border-bottom: 0;
}
.chevron {
    transition: transform 0.3s;
    width: 12px;
    color: #0250d9;
    font-size: 17px;
    line-height: 1;
    text-align: center;
}
.chevron.down {
    transform: rotate(90deg);
}
.panel-slide {
    display: grid;
    grid-template-rows: 0fr;
    transition: grid-template-rows 0.6s ease-in-out;
}
.panel-slide.open {
    grid-template-rows: 1fr;
}
.panel-clip {
    min-height: 0;
    overflow: hidden;
}
.chain-text {
    flex: 1;
    min-width: 0;
}
.chain-name {
    margin-right: 6px;
    color: #444;
    font-weight: 700;
}
.chain-meta {
    display: flex;
    align-items: center;
    gap: 6px;
    color: var(--muted);
    font-size: 12px;
}
.badge {
    display: inline-block;
    margin-right: 4px;
    padding: 0 6px;
    border-radius: 4px;
    font-size: 10.5px;
    font-weight: 700;
    letter-spacing: 0.02em;
    text-transform: uppercase;
}
.badge-run {
    background: #e5f1fb;
    color: var(--run);
}
.badge-ok {
    background: #e6f3e9;
    color: var(--ok);
}
.badge-bad {
    background: #fdecea;
    color: var(--bad);
}
.badge-new {
    background: #fde7a0;
    color: #5c3b00;
}
.dots {
    display: inline-flex;
    gap: 3px;
}
.dots i {
    width: 7px;
    height: 7px;
    border-radius: 50%;
}
.dots .ok {
    background: var(--ok);
}
.dots .bad {
    background: var(--bad);
}
.dots .skip {
    background: var(--skip);
}
.requeue {
    padding: 1px 9px;
    border: 1px solid #0250d9;
    border-radius: 999px;
    color: #0250d9;
    font-size: 12px;
    font-weight: 600;
}
.panel {
    padding: 8px 14px 6px 12px;
    border-top: 1px solid var(--line);
    border-bottom: 1px solid var(--line);
    background: #f3f6f9;
}
.progress-text {
    display: flex;
    justify-content: space-between;
    gap: 8px;
    color: var(--muted);
    font-size: 12px;
}
.bar {
    height: 5px;
    margin: 4px 0 6px;
    overflow: hidden;
    border-radius: 3px;
    background: var(--line);
}
.bar i {
    display: block;
    height: 100%;
    background: var(--ok);
    transition: width 0.4s;
}
.step {
    position: relative;
    display: flex;
    gap: 9px;
    padding: 4px 6px 4px 4px;
    border: 1px solid transparent;
    border-radius: 6px;
}
.step:not(.last)::before {
    content: '';
    position: absolute;
    top: 22px;
    bottom: -5px;
    left: 12px;
    width: 2px;
    background: #c9d7e3;
}
.step.added {
    background: linear-gradient(90deg, #fff7e0, transparent 70%);
}
.step.current {
    border-color: var(--run);
    background: #fff;
}
.glyph {
    position: relative;
    z-index: 1;
    flex-shrink: 0;
    width: 18px;
    height: 18px;
    margin-top: 1px;
    border-radius: 50%;
    color: #fff;
    font-size: 11px;
    line-height: 18px;
    text-align: center;
}
.glyph-ok {
    background: var(--ok);
    animation: pop 0.3s;
}
.glyph-run {
    border: 2px solid var(--run);
    border-right-color: transparent;
    background: #fff;
    animation: spin 1s linear infinite;
}
.glyph-wait {
    border: 2px solid #8a8a8a;
    background: #fff;
}
.step-name {
    margin-right: 6px;
    font-weight: 700;
}
.step-status {
    margin-right: 4px;
    font-size: 12px;
    font-weight: 600;
}
.status-ok {
    color: var(--ok);
}
.status-run {
    color: var(--run);
}
.status-wait {
    color: var(--muted);
}
.step-meta {
    display: flex;
    align-items: center;
    gap: 6px;
    color: var(--muted);
    font-size: 12px;
}
.tag {
    padding: 0 5px;
    border: 1px solid var(--line);
    border-radius: 4px;
    background: #fff;
}
.strip {
    display: inline-flex;
    gap: 2px;
}
.strip i {
    width: 7px;
    height: 7px;
    border-radius: 1px;
    background: var(--line);
    transition: background 0.2s;
}
.strip .sq-ok {
    background: var(--ok);
}
.strip .sq-run {
    background: var(--run);
}
.foot {
    display: flex;
    justify-content: space-between;
    padding: 7px 14px;
    border-top: 1px solid var(--line);
    color: #8a8a8a;
    font-size: 11.5px;
}
.arrive-enter-active {
    transition: all 0.4s;
    overflow: hidden;
}
.arrive-enter-from {
    max-height: 0;
    opacity: 0;
    padding-top: 0;
    padding-bottom: 0;
}
.arrive-enter-to {
    max-height: 70px;
}
.arrive-leave-active {
    transition: all 0.4s;
    overflow: hidden;
}
.arrive-leave-from {
    max-height: 70px;
}
.arrive-leave-to {
    max-height: 0;
    opacity: 0;
}
.arrive-move {
    transition: transform 0.4s;
}
@keyframes spin {
    to {
        transform: rotate(360deg);
    }
}
@keyframes pop {
    from {
        transform: scale(0.5);
    }
}
@keyframes pulse {
    50% {
        opacity: 0.35;
    }
}
@media (prefers-reduced-motion: reduce) {
    .demo * {
        animation: none !important;
        transition: none !important;
    }
}
</style>
