import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { setTimeout as delay } from 'node:timers/promises';
import { chromium } from 'playwright';

const baseUrl = 'http://127.0.0.1:4173';

async function startServer() {
  const server = spawn('python3', ['-m', 'http.server', '4173'], {
    cwd: new URL('..', import.meta.url),
    stdio: 'ignore',
  });
  await delay(350);
  return server;
}

async function run() {
  const server = await startServer();
  const browser = await chromium.launch({ channel: 'chrome', headless: true });
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  const pageErrors = [];
  page.on('pageerror', (error) => pageErrors.push(error));
  try {
    await page.goto(baseUrl, { waitUntil: 'domcontentloaded' });
    assert.equal(
      await page.locator('[data-testid="notch-window"]').isVisible(),
      true,
      'notch window should be visible',
    );
    assert.match(await page.locator('[data-testid="quota-wave-five"]').getAttribute('d'), /^M/);
    assert.match(await page.locator('[data-testid="quota-wave-weekly"]').getAttribute('d'), /^M\s*672\s+1/);
    if (process.env.UPDATE_SCREENSHOTS === '1') {
      await page.screenshot({ path: new URL('../artifacts/first-prototype-collapsed.png', import.meta.url).pathname, fullPage: true });
    }

    const collapsedWidth = await page.locator('[data-testid="notch-window"]').evaluate((root) => root.getBoundingClientRect().width);
    await page.locator('[data-testid="notch-toggle"]').hover();
    await page.waitForTimeout(240);
    const hoverShape = await page.locator('[data-testid="notch-window"]').evaluate((root) => {
      const wave = root.querySelector('[data-testid="quota-wave-five"]');
      const shimmer = root.querySelector('[data-testid="quota-wave-shimmer-five"]');
      const style = getComputedStyle(wave);
      return {
        rootWidth: root.getBoundingClientRect().width,
        strokeWidth: parseFloat(style.strokeWidth),
        baseAnimationName: style.animationName,
        baseDashOffset: style.strokeDashoffset,
        shimmerAnimationName: shimmer ? getComputedStyle(shimmer).animationName : '',
      };
    });
    assert.ok(hoverShape.rootWidth > collapsedWidth, 'hover should slightly enlarge the notch silhouette');
    assert.ok(hoverShape.strokeWidth > 2.2, 'hover should make the quota contour thicker');
    assert.equal(hoverShape.baseAnimationName, 'none', 'the quota line itself should remain still');
    assert.equal(hoverShape.baseDashOffset, '0px', 'the static quota line must not slide');
    assert.match(hoverShape.shimmerAnimationName, /contour-glow-marquee/, 'hover should animate a separate moving light');
    if (process.env.UPDATE_SCREENSHOTS === '1') {
      await page.screenshot({ path: new URL('../artifacts/first-prototype-hover.png', import.meta.url).pathname, fullPage: true });
    }
    await page.mouse.move(0, 700);
    await page.locator('[data-testid="notch-toggle"]').click();
    assert.equal(await page.locator('[data-testid="details-panel"]').isVisible(), true, 'details panel should open');
    await page.waitForTimeout(520);
    const expandedShape = await page.locator('[data-testid="notch-window"]').evaluate((root) => {
      const panel = root.querySelector('[data-testid="details-panel"]');
      const hitArea = root.querySelector('[data-testid="notch-toggle"]');
      const contour = root.querySelector('.wave-contour');
      return {
        rootRadius: getComputedStyle(root).borderBottomLeftRadius,
        rootWidth: root.getBoundingClientRect().width,
        panelShadow: getComputedStyle(panel).boxShadow,
        contourGap: Math.abs(hitArea.getBoundingClientRect().bottom - contour.getBoundingClientRect().bottom),
      };
    });
    assert.ok(parseFloat(expandedShape.rootRadius) >= 30, 'expanded state should become one rounded notch panel');
    assert.ok(expandedShape.rootWidth > collapsedWidth, 'expanded notch should grow from its original silhouette');
    assert.equal(expandedShape.panelShadow, 'none', 'details must be part of the enlarged notch, not a second floating panel');
    assert.ok(expandedShape.contourGap <= 1, 'wave contour should hug the notch edge');
    assert.match(await page.locator('[data-testid="quota-five-hour"]').innerText(), /58%/);
    assert.match(await page.locator('[data-testid="quota-weekly"]').innerText(), /31%/);

    await page.locator('[data-testid="tab-local-usage"]').click();
    assert.equal(await page.locator('[data-testid="source-local-usage"]').isVisible(), true, 'Local usage panel should show');
    assert.equal(await page.locator('[data-testid="source-aiusage"]').isVisible(), false, 'AIUsage panel should hide');
    assert.match(await page.locator('[data-testid="source-local-usage"]').innerText(), /日总 Token/);

    await page.evaluate(() => window.__codexNotchDemo.setDemoStatus('error'));
    assert.equal(await page.locator('[data-testid="notch-window"]').getAttribute('data-status'), 'error');
    assert.equal(pageErrors.length, 0, `page errors: ${pageErrors.map((error) => error.message).join('; ')}`);
    if (process.env.UPDATE_SCREENSHOTS === '1') {
      await page.screenshot({ path: new URL('../artifacts/first-prototype-expanded.png', import.meta.url).pathname, fullPage: true });
    }
  } finally {
    await browser.close();
    server.kill();
  }
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
