const fs = require('fs');
const { chromium } = require('playwright');

const [loginFile, stage, outDir, chromiumPath] = process.argv.slice(2);
const loginUrl = JSON.parse(fs.readFileSync(loginFile, 'utf8')).result.url;
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

const openCard = async (browser, viewport, deviceScaleFactor) => {
    const context = await browser.newContext({ viewport, deviceScaleFactor });
    const page = await context.newPage();
    await page.goto(loginUrl, { waitUntil: 'load', timeout: 120000 });
    await page.waitForSelector('c-async-job-timeline', { timeout: 120000 });
    await sleep(8000);
    return page;
};

const shotOf = page => async (locator, name) => {
    await locator.scrollIntoViewIfNeeded();
    await sleep(300);
    const box = await locator.boundingBox();
    const scrollY = await page.evaluate(() => window.scrollY);
    await page.screenshot({
        path: `${outDir}/${name}.png`,
        fullPage: true,
        clip: { x: Math.max(0, box.x - 10), y: box.y + scrollY - 10, width: box.width + 20, height: box.height + 20 }
    });
    console.log(name);
};

const chainNamed = (page, card, name) =>
    card
        .locator('c-async-job-sequence')
        .filter({ has: page.locator('.chain-head [data-id="name"]', { hasText: name }) })
        .first();

const showAllRows = card =>
    card.locator('.scroller').evaluate(el => {
        el.style.height = 'auto';
        el.style.overflow = 'visible';
    });

const settled = async browser => {
    const page = await openCard(browser, { width: 1440, height: 1800 }, 2);
    const shot = shotOf(page);
    const card = page.locator('c-async-job-timeline').first();
    await showAllRows(card);
    await sleep(300);
    await shot(card, 'list');
    const fulfilment = chainNamed(page, card, 'Order fulfilment pipeline');
    await fulfilment.locator('.chain-head').click();
    await sleep(600);
    const failedStep = fulfilment.locator('c-async-job-step', { hasText: 'Commission split' }).first();
    await failedStep.locator('[data-id="row"] .name').click();
    await sleep(600);
    await shot(fulfilment, 'failed-chain');
    await failedStep.locator('[data-id="row"] .name').click();
    await fulfilment.locator('.chain-head').click();
    await sleep(400);
    const reprice = chainNamed(page, card, 'Reprice order lines');
    await reprice.locator('.chain-head').click();
    await sleep(500);
    await reprice.locator('c-async-job-step').first().locator('[data-id="row"] .name').click();
    await sleep(500);
    await shot(reprice, 'failed-chunk');
};

const map = async browser => {
    const page = await openCard(browser, { width: 2000, height: 1300 }, 1.5);
    const card = page.locator('c-async-job-timeline').first();
    const fulfilment = chainNamed(page, card, 'Order fulfilment pipeline');
    await fulfilment.locator('.chain-actions button').last().click();
    await sleep(500);
    await fulfilment.locator('lightning-menu-item', { hasText: 'Chain map' }).locator('visible=true').first().click();
    await sleep(3000);
    const header = await page.locator('.slds-modal__header').locator('visible=true').first().boundingBox();
    const footer = await page.locator('.slds-modal__footer').locator('visible=true').first().boundingBox();
    await page.screenshot({
        path: `${outDir}/chain-map.png`,
        clip: { x: header.x, y: header.y, width: header.width, height: footer.y + footer.height - header.y }
    });
    console.log('chain-map');
};

const running = async browser => {
    const page = await openCard(browser, { width: 1440, height: 1800 }, 2);
    const shot = shotOf(page);
    const cards = page.locator('c-async-job-timeline');
    await showAllRows(cards.nth(0));
    await showAllRows(cards.nth(1));
    const chunkStep = cards.nth(0).locator('c-async-job-step', { hasText: 'Tax 16 lines' }).first();
    for (let waited = 0; waited < 120; waited++) {
        const summary = await chunkStep.locator('[data-id="strip-summary"]').textContent({ timeout: 1000 }).catch(() => '');
        if (/page [2-6] of 8/.test(summary)) break;
        await sleep(1000);
    }
    await shot(cards.nth(0), 'running');
    await shot(cards.nth(1), 'sidebar');
};

const stages = { settled, map, running };

(async () => {
    const browser = await chromium.launch({ headless: true, executablePath: chromiumPath || undefined });
    await stages[stage](browser);
    await browser.close();
})().catch(error => {
    console.error('FAILED', error.message.split('\n')[0]);
    process.exit(1);
});
