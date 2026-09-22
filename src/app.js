import {
  formatCompactNumber,
  formatCurrency,
  formatResetTime,
  getPrototypeState,
} from './data-adapters.js';

const root = document.querySelector('[data-testid="notch-window"]');
const toggle = document.querySelector('[data-testid="notch-toggle"]');
const panel = document.querySelector('[data-testid="details-panel"]');
const statusDot = document.querySelector('[data-testid="status-dot"]');
const waveFive = document.querySelector('[data-testid="quota-wave-five"]');
const waveWeekly = document.querySelector('[data-testid="quota-wave-weekly"]');
const waveFiveMask = document.querySelector('[data-testid="quota-wave-mask-five"]');
const waveWeeklyMask = document.querySelector('[data-testid="quota-wave-mask-weekly"]');
const waveFiveShimmer = document.querySelector('[data-testid="quota-wave-shimmer-five"]');
const waveWeeklyShimmer = document.querySelector('[data-testid="quota-wave-shimmer-weekly"]');

const state = {
  ...getPrototypeState(),
  expanded: false,
  activeSource: 'aiusage',
};

function escapeHtml(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

export function buildWavePath(fiveHourPercent, weeklyPercent, width = 760, height = 56) {
  const left = Math.round(width * 0.116);
  const center = Math.round(width * 0.5);
  const right = Math.round(width * 0.884);
  const bottom = Math.round(height - 6);
  const curve = Math.round(width * 0.041);
  const rise = Math.round(height * 0.55);
  const safeFive = Math.max(0, Math.min(100, Number(fiveHourPercent) || 0));
  const safeWeekly = Math.max(0, Math.min(100, Number(weeklyPercent) || 0));
  return {
    leftPath: `M ${left} 1 C ${left} ${rise} ${left + curve} ${bottom} ${left + curve * 2} ${bottom} H ${center}`,
    rightPath: `M ${right} 1 C ${right} ${rise} ${right - curve} ${bottom} ${right - curve * 2} ${bottom} H ${center}`,
    five: safeFive,
    weekly: safeWeekly,
  };
}

function updateWave() {
  const geometry = buildWavePath(state.quota.fiveHour.usedPercent, state.quota.weekly.usedPercent);
  waveFive.setAttribute('d', geometry.leftPath);
  waveWeekly.setAttribute('d', geometry.rightPath);
  waveFiveMask.setAttribute('d', geometry.leftPath);
  waveWeeklyMask.setAttribute('d', geometry.rightPath);
  waveFiveShimmer.setAttribute('d', geometry.leftPath);
  waveWeeklyShimmer.setAttribute('d', geometry.rightPath);
  const fiveLength = Math.max(0, Math.min(500, geometry.five * 5));
  const weeklyLength = Math.max(0, Math.min(500, geometry.weekly * 5));
  waveFive.style.strokeDasharray = `${fiveLength} ${500 - fiveLength}`;
  waveWeekly.style.strokeDasharray = `${weeklyLength} ${500 - weeklyLength}`;
  waveFiveMask.style.strokeDasharray = `${fiveLength} ${500 - fiveLength}`;
  waveWeeklyMask.style.strokeDasharray = `${weeklyLength} ${500 - weeklyLength}`;
}

function renderCollapsedState() {
  root.dataset.status = state.quota.status;
  statusDot.setAttribute('aria-label', `状态：${state.quota.status}`);
  toggle.setAttribute('aria-expanded', String(state.expanded));
  root.classList.toggle('is-expanded', state.expanded);
  updateWave();
}

function renderQuotaCard(label, quota, className) {
  const percent = quota.usedPercent === null ? '—' : `${Math.round(quota.usedPercent)}%`;
  return `<article class="quota-card ${className}" data-testid="quota-${className === 'five' ? 'five-hour' : 'weekly'}">
    <span class="card-label">${label}</span>
    <div class="card-value">${percent}</div>
    <div class="reset">${escapeHtml(formatResetTime(quota.resetAt))}</div>
  </article>`;
}

function renderAiUsagePanel() {
  const summary = state.aiUsage;
  const tools = summary.topToolCalls.slice(0, 3).map((tool) => `<span class="tool-chip">${escapeHtml(tool.name)} · ${tool.count}</span>`).join('');
  return `<section class="source-panel" data-testid="source-aiusage" data-source="aiusage">
    <div class="source-kicker">AIUSAGE · 本地记录</div>
    <div class="stat-grid">
      <div class="stat"><span>总 Token</span><strong>${formatCompactNumber(summary.totalTokens)}</strong></div>
      <div class="stat"><span>成本</span><strong>${formatCurrency(summary.totalCost)}</strong></div>
      <div class="stat"><span>会话</span><strong>${summary.totalSessions}</strong></div>
      <div class="stat"><span>活动天数</span><strong>${summary.activeDays}</strong></div>
    </div>
    <div class="source-foot"><span>输入 ${formatCompactNumber(summary.inputTokens)} · 输出 ${formatCompactNumber(summary.outputTokens)}</span><span>缓存 ${formatCompactNumber(summary.cacheReadTokens)}</span></div>
    <div class="tool-list">${tools}</div>
  </section>`;
}

function renderLocalUsagePanel() {
  const daily = state.localUsage;
  const uploadClass = daily.uploadCode === 0 ? 'upload-ok' : 'upload-warn';
  return `<section class="source-panel" data-testid="source-local-usage" data-source="local-usage" hidden>
    <div class="source-kicker">LOCAL USAGE · 上报统计</div>
    <div class="stat-grid">
      <div class="stat"><span>日总 Token</span><strong>${formatCompactNumber(daily.totalTokens)}</strong></div>
      <div class="stat"><span>回合</span><strong>${daily.turns}</strong></div>
      <div class="stat"><span>推理输出</span><strong>${formatCompactNumber(daily.reasoningOutputTokens)}</strong></div>
      <div class="stat"><span>日期</span><strong>${escapeHtml(daily.date.slice(5))}</strong></div>
    </div>
    <div class="source-foot"><span>输入 ${formatCompactNumber(daily.inputTokens)} · 缓存 ${formatCompactNumber(daily.cachedInputTokens)}</span><span class="${uploadClass}">上传 ${escapeHtml(daily.uploadMessage)}</span></div>
  </section>`;
}

function renderDetailsPanel() {
  panel.innerHTML = `<div class="detail-head">
    <div><h2 class="detail-title">Codex 用量概览</h2><p class="detail-subtitle">实时额度 · ${escapeHtml(state.session.lastActivity)}</p></div>
    <button class="detail-close" data-testid="detail-close" type="button" aria-label="收起">×</button>
  </div>
  <div class="quota-grid">${renderQuotaCard('5 小时额度', state.quota.fiveHour, 'five')}${renderQuotaCard('周额度', state.quota.weekly, 'week')}</div>
  <div class="session-row" data-testid="session-status"><span class="session-orb"></span><div class="session-copy"><strong>${escapeHtml(state.session.label)} · ${escapeHtml(state.session.status)}</strong><span>${escapeHtml(state.session.model)}</span></div><span class="session-callcount">${state.session.toolCalls} 次调用</span></div>
  <div class="source-tabs" role="tablist" aria-label="统计来源">
    <button class="source-tab" data-testid="tab-aiusage" data-source-tab="aiusage" role="tab" aria-selected="${state.activeSource === 'aiusage'}" type="button">AIUsage</button>
    <button class="source-tab" data-testid="tab-local-usage" data-source-tab="local-usage" role="tab" aria-selected="${state.activeSource === 'local-usage'}" type="button">Local usage</button>
  </div>
  <div class="source-panels">${renderAiUsagePanel()}${renderLocalUsagePanel()}</div>`;
  const activePanel = panel.querySelector(`[data-source="${state.activeSource}"]`);
  const inactivePanel = panel.querySelector(`[data-source="${state.activeSource === 'aiusage' ? 'local-usage' : 'aiusage'}"]`);
  activePanel.hidden = false;
  inactivePanel.hidden = true;
}

function render() {
  renderCollapsedState();
  if (state.expanded) {
    panel.hidden = false;
    renderDetailsPanel();
  } else {
    panel.hidden = true;
    panel.innerHTML = '';
  }
}

function toggleExpanded(nextValue = !state.expanded) {
  state.expanded = nextValue;
  render();
}

function setDemoStatus(status) {
  state.quota.status = status;
  renderCollapsedState();
}

toggle.addEventListener('click', () => toggleExpanded());

document.addEventListener('click', (event) => {
  const sourceTab = event.target.closest('[data-source-tab]');
  if (sourceTab) {
    state.activeSource = sourceTab.dataset.sourceTab;
    renderDetailsPanel();
    return;
  }
  if (event.target.closest('[data-testid="detail-close"]')) {
    toggleExpanded(false);
    return;
  }
  const statusButton = event.target.closest('[data-status-control]');
  if (statusButton) {
    setDemoStatus(statusButton.dataset.statusControl);
    return;
  }
  if (state.expanded && !event.target.closest('[data-testid="notch-window"]')) toggleExpanded(false);
});

document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape' && state.expanded) toggleExpanded(false);
  const sourceTab = event.target.closest('[data-source-tab]');
  if (sourceTab && (event.key === 'Enter' || event.key === ' ')) {
    event.preventDefault();
    state.activeSource = sourceTab.dataset.sourceTab;
    renderDetailsPanel();
  }
});

window.__codexNotchDemo = { setDemoStatus, getState: () => structuredClone(state) };
render();
