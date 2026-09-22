# Codex Notch Companion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a first high-fidelity, interactive HTML prototype of a Codex notch companion that shows 5-hour and weekly quota progress as a continuous wave contour inside an elongated notch, then expands into separated AIUsage and Local usage statistics.

**Architecture:** Use a dependency-free static prototype served from `index.html`. Keep data normalization in `src/data-adapters.js`, visual state and interactions in `src/app.js`, and styles in `src/styles.css`. The first build uses explicit mock fixtures that match the verified local aiusage/Local usage field contracts; adapter functions are ready for later local API/file bridges without performing uploads or credential access.

**Tech Stack:** HTML5, CSS custom properties, inline SVG path for the wave contour, vanilla JavaScript modules, Playwright CLI for browser verification.

## Global Constraints

- Collapsed state is one elongated black notch window, not a floating card or two independent wings.
- Collapsed state shows only the contour, one status dot, and no percentage labels or stat cards.
- The contour uses coral/orange for the 5-hour quota and mint for the weekly quota.
- AIUsage and Local usage statistics remain separate and are never summed into one total.
- Prototype does not write to, upload from, or reconfigure aiusage or Local usage.
- No native macOS `NSPanel`/`NSWindow`, OAuth, Keychain, LaunchAgent, or real background process in this iteration.
- Keep each HTML/CSS/JS file under 1000 lines; comments must record assumptions and placeholders.

---

### Task 1: Scaffold the prototype shell and test surface

**Files:**
- Create: `index.html`
- Create: `src/styles.css`
- Create: `src/app.js`
- Create: `src/data-adapters.js`
- Create: `tests/prototype.spec.js`
- Create: `package.json`
- Create: `README.md`

**Interfaces:**
- `index.html` loads `/src/styles.css` and `/src/app.js` as an ES module.
- `src/app.js` imports `getPrototypeState`, `formatCompactNumber`, and `normalizeQuotaState` from `src/data-adapters.js`.
- `tests/prototype.spec.js` opens `index.html` through a local static server and relies on `data-testid` attributes defined in `index.html`.

- [ ] **Step 1: Add the package and test command.**

```json
{
  "name": "codex-notch-companion",
  "private": true,
  "type": "module",
  "scripts": {
    "test:ui": "node tests/prototype.spec.js"
  }
}
```

- [ ] **Step 2: Add the semantic page shell.**

```html
<main class="desktop-stage" data-testid="desktop-stage">
  <section class="notch-window" data-testid="notch-window" aria-label="Codex usage companion">
    <button class="notch-hit-area" data-testid="notch-toggle" aria-expanded="false" aria-controls="details-panel">
      <span class="wave-contour" aria-hidden="true"><svg viewBox="0 0 760 48" preserveAspectRatio="none"><path data-testid="quota-wave" /></svg></span>
      <span class="status-dot" data-testid="status-dot" aria-hidden="true"></span>
    </button>
    <div class="details-panel" id="details-panel" data-testid="details-panel" hidden></div>
  </section>
</main>
<script type="module" src="/src/app.js"></script>
```

- [ ] **Step 3: Add the static-server test harness.**

`tests/prototype.spec.js` must start `python3 -m http.server 4173 --directory <project-root>` with `child_process.spawn`, open `http://127.0.0.1:4173`, and close the child in a `finally` block. The first assertion must check that `[data-testid="notch-window"]` is visible before any interaction.

- [ ] **Step 4: Run the shell test once.**

Run: `npm run test:ui`

Expected: FAIL with a clear assertion that the wave path or details panel behavior is not implemented yet.

### Task 2: Implement the data adapter boundary

**Files:**
- Modify: `src/data-adapters.js`
- Modify: `src/app.js`
- Create: `fixtures/aiusage-summary.json`
- Create: `fixtures/local-daily.json`

**Interfaces:**
- `normalizeQuotaState(raw)` returns `{ fiveHour, weekly, status, queriedAt }`.
- `normalizeAiUsageSummary(raw)` returns `{ totalTokens, inputTokens, outputTokens, cacheReadTokens, thinkingTokens, totalCost, totalSessions, topToolCalls }`.
- `normalizeLocalDailyRow(raw)` returns `{ date, turns, inputTokens, cachedInputTokens, outputTokens, reasoningOutputTokens, totalTokens, uploadCode, uploadMessage, lastSuccessAt }`.
- `getPrototypeState()` returns `{ quota, session, aiUsage, localUsage }` using fixture data only.

- [ ] **Step 1: Write fixture payloads using verified field names.**

`fixtures/aiusage-summary.json` must include the `/api/summary` fields `inputTokens`, `outputTokens`, `cacheReadTokens`, `thinkingTokens`, `totalTokens`, `totalCost`, `totalSessions`, and `topToolCalls`. `fixtures/local-daily.json` must include the CSV-equivalent names `date`, `turns`, `input_tokens`, `cached_input_tokens`, `output_tokens`, `reasoning_output_tokens`, `total_tokens`, `upload_code`, `upload_message`, and `last_success_at`.

- [ ] **Step 2: Add normalizers with explicit numeric fallbacks.**

```js
export function normalizeQuotaState(raw = {}) {
  const windows = raw.rate_limit ?? {};
  const toWindow = (window = {}, fallbackName) => ({
    name: fallbackName,
    usedPercent: Number.isFinite(Number(window.used_percent)) ? Number(window.used_percent) : null,
    resetAt: window.reset_at ? new Date(Number(window.reset_at) * 1000).toISOString() : null,
  });
  return {
    fiveHour: toWindow(windows.primary_window, '5-hour'),
    weekly: toWindow(windows.secondary_window, 'weekly'),
    status: raw.success === false ? 'error' : 'ready',
    queriedAt: raw.queriedAt ?? null,
  };
}
```

- [ ] **Step 3: Keep adapter errors local and non-mutating.**

`getPrototypeState()` must never call `fetch`, write files, or invoke a CLI. It returns `status: 'stale'` when a fixture field is missing, so the UI can prove the degraded state without touching user credentials or upload services.

- [ ] **Step 4: Run the adapter test surface.**

Run: `node -e "import('./src/data-adapters.js').then(m => console.log(m.normalizeQuotaState({rate_limit:{primary_window:{used_percent:58},secondary_window:{used_percent:31}}})))"`

Expected: printed object contains `fiveHour.usedPercent: 58` and `weekly.usedPercent: 31`.

### Task 3: Build the collapsed elongated-notch visual

**Files:**
- Modify: `index.html`
- Modify: `src/styles.css`
- Modify: `src/app.js`

**Interfaces:**
- `renderCollapsedState(state)` updates the wave path, state dot, and `data-status` without adding text inside the collapsed notch.
- `buildWavePath(fiveHourPercent, weeklyPercent, width, height)` returns a valid SVG path string for the two-color contour.
- `setQuotaWave(path, state)` sets `stroke-dasharray`, `stroke-dashoffset`, and CSS variables `--five-hour-progress` / `--weekly-progress`.

- [ ] **Step 1: Write the wave-path unit assertion.**

```js
const path = buildWavePath(58, 31, 760, 48);
assert.match(path, /^M\s*0\s+\d+/);
assert.match(path, /C/);
assert.match(path, /760\s+\d+/);
```

- [ ] **Step 2: Implement the contour geometry.**

The path must start at the left inner curve, dip into a shallow wave along the bottom, and rise into the right inner curve. Split the path into two `<path>` elements with the same geometry: the first is clipped to the left quota segment and uses coral/orange; the second is clipped to the right quota segment and uses mint. Do not add a label layer to the collapsed state.

- [ ] **Step 3: Implement motion and degraded states.**

`working` applies a subtle 8-second `stroke-dashoffset` animation; `stale` reduces opacity to `0.45`; `error` changes the status dot to coral-red and leaves the last valid contour visible. Respect `prefers-reduced-motion` by disabling the animation.

- [ ] **Step 4: Add the collapsed interaction.**

The click handler must toggle `aria-expanded`, remove/add the `hidden` attribute on `#details-panel`, and add the `is-expanded` class to `.notch-window`. Clicking the notch must not navigate or submit a form.

- [ ] **Step 5: Run the first visual test.**

Run: `npm run test:ui`

Expected: the page loads, the notch window is visible, the wave path exists, and clicking `[data-testid="notch-toggle"]` changes `aria-expanded` from `false` to `true`.

### Task 4: Implement the expanded detail panel

**Files:**
- Modify: `index.html`
- Modify: `src/styles.css`
- Modify: `src/app.js`

**Interfaces:**
- `renderDetailsPanel(state)` renders quota cards, current session, and source tabs into `#details-panel`.
- `renderSourcePanel(source, state)` renders exactly one source panel at a time: `aiusage` or `localUsage`.

- [ ] **Step 1: Add expanded markup targets.**

The panel must include `data-testid="quota-five-hour"`, `data-testid="quota-weekly"`, `data-testid="session-status"`, `data-testid="source-aiusage"`, `data-testid="source-local-usage"`, `data-testid="tab-aiusage"`, and `data-testid="tab-local-usage"`.

- [ ] **Step 2: Render the quota cards and session row.**

Use exact fixture values for the prototype, but format them through `formatCompactNumber` and `formatRelativeTime`. The visible copy must distinguish `5 小时额度` and `周额度`, and the panel must show model/session status without exposing local file paths or credentials.

- [ ] **Step 3: Render AIUsage and Local usage separately.**

AIUsage panel shows local total tokens, cost, sessions, input/output/cache/thinking breakdown, and top tool calls. Local usage panel shows the daily row, total tokens, turns, upload status, and last success time. No combined total is rendered.

- [ ] **Step 4: Add source-tab interaction and keyboard support.**

Clicking each tab toggles `aria-selected`, hides the other panel, and keeps the notch expanded. `Enter` and `Space` on the tabs must have the same effect as click.

- [ ] **Step 5: Run the interaction test.**

Run: `npm run test:ui`

Expected: opening the notch reveals quota/session content; clicking Local usage reveals `[data-testid="source-local-usage"]` and hides `[data-testid="source-aiusage"]`; clicking AIUsage reverses it.

### Task 5: Add state controls and responsive polish

**Files:**
- Modify: `index.html`
- Modify: `src/styles.css`
- Modify: `src/app.js`
- Modify: `README.md`

**Interfaces:**
- `setDemoStatus(status)` supports `idle`, `working`, `stale`, and `error` for visual review.
- `window.__codexNotchDemo` exposes `{ setDemoStatus, getState }` for Playwright and manual review.

- [ ] **Step 1: Add a non-production demo control rail outside the notch.**

The control rail is visible only in the prototype review page, never inside the collapsed notch. Buttons use `data-testid="status-idle"`, `data-testid="status-working"`, `data-testid="status-stale"`, and `data-testid="status-error"`.

- [ ] **Step 2: Add responsive constraints.**

At viewport widths below `900px`, scale the notch width with `min(760px, calc(100vw - 32px))`, preserve the bottom contour, and keep the main mock window content visible. At `prefers-reduced-motion: reduce`, set all transition/animation durations to `0ms`.

- [ ] **Step 3: Document local run instructions.**

`README.md` must include:

```bash
cd /Users/inathan/Documents/inathan/code/codex-notch-companion
python3 -m http.server 4173
open http://127.0.0.1:4173
```

It must state that fixtures are used in v1, aiusage/Local usage are read-only integration targets, and no uploads are triggered.

### Task 6: Verify visually and commit the first prototype

**Files:**
- Modify: `tests/prototype.spec.js`
- Create: `artifacts/first-prototype.png`

**Interfaces:**
- The test covers collapsed state, expanded state, source switching, and error state.

- [ ] **Step 1: Add Playwright assertions.**

The test must assert:

```js
await page.locator('[data-testid="notch-toggle"]').click();
await expect(page.locator('[data-testid="details-panel"]')).toBeVisible();
await page.locator('[data-testid="tab-local-usage"]').click();
await expect(page.locator('[data-testid="source-local-usage"]')).toBeVisible();
await expect(page.locator('[data-testid="source-aiusage"]')).toBeHidden();
```

It must also set `window.__codexNotchDemo.setDemoStatus('error')` and assert `data-status="error"` on the notch window.

- [ ] **Step 2: Capture a screenshot.**

Run: `npx playwright screenshot --device="Desktop Chrome" http://127.0.0.1:4173 /Users/inathan/Documents/inathan/code/codex-notch-companion/artifacts/first-prototype.png`

Expected: screenshot shows the elongated black notch, thin wave contour, and no collapsed-state labels.

- [ ] **Step 3: Run the full verification.**

Run: `npm run test:ui`

Expected: PASS with zero page errors and all interaction assertions passing.

- [ ] **Step 4: Review the diff and commit.**

```bash
git add index.html src styles.css fixtures tests package.json README.md artifacts/first-prototype.png
git commit -m "feat: add codex notch usage prototype"
```

