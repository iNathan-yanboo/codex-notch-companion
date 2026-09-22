import aiUsageSummary from '../fixtures/aiusage-summary.json' with { type: 'json' };
import localDaily from '../fixtures/local-daily.json' with { type: 'json' };

const now = Date.now();

function numberOrNull(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function toResetIso(value) {
  const timestamp = numberOrNull(value);
  if (timestamp === null) return null;
  return new Date(timestamp > 10_000_000_000 ? timestamp : timestamp * 1000).toISOString();
}

function normalizeWindow(window = {}, name) {
  return {
    name,
    usedPercent: numberOrNull(window.used_percent),
    resetAt: toResetIso(window.reset_at),
  };
}

export function normalizeQuotaState(raw = {}) {
  const rateLimit = raw.rate_limit ?? {};
  const fiveHour = normalizeWindow(rateLimit.primary_window, '5-hour');
  const weekly = normalizeWindow(rateLimit.secondary_window, 'weekly');
  const missing = fiveHour.usedPercent === null || weekly.usedPercent === null;
  return {
    fiveHour,
    weekly,
    status: raw.success === false ? 'error' : missing ? 'stale' : 'ready',
    queriedAt: raw.queriedAt ?? null,
  };
}

export function normalizeAiUsageSummary(raw = {}) {
  return {
    inputTokens: numberOrNull(raw.inputTokens) ?? 0,
    outputTokens: numberOrNull(raw.outputTokens) ?? 0,
    cacheReadTokens: numberOrNull(raw.cacheReadTokens) ?? 0,
    cacheWriteTokens: numberOrNull(raw.cacheWriteTokens) ?? 0,
    thinkingTokens: numberOrNull(raw.thinkingTokens) ?? 0,
    totalTokens: numberOrNull(raw.totalTokens) ?? 0,
    totalCost: numberOrNull(raw.totalCost) ?? 0,
    activeDays: numberOrNull(raw.activeDays) ?? 0,
    totalSessions: numberOrNull(raw.totalSessions) ?? 0,
    topToolCalls: Array.isArray(raw.topToolCalls) ? raw.topToolCalls : [],
  };
}

export function normalizeLocalDailyRow(raw = {}) {
  return {
    date: raw.date ?? '',
    source: raw.source ?? 'local-codex',
    turns: numberOrNull(raw.turns) ?? 0,
    inputTokens: numberOrNull(raw.input_tokens) ?? 0,
    cachedInputTokens: numberOrNull(raw.cached_input_tokens) ?? 0,
    outputTokens: numberOrNull(raw.output_tokens) ?? 0,
    reasoningOutputTokens: numberOrNull(raw.reasoning_output_tokens) ?? 0,
    totalTokens: numberOrNull(raw.total_tokens) ?? 0,
    uploadCode: numberOrNull(raw.upload_code),
    uploadMessage: raw.upload_message ?? 'unknown',
    lastSuccessAt: raw.last_success_at ?? null,
  };
}

export function getPrototypeState() {
  return {
    quota: normalizeQuotaState({
      success: true,
      queriedAt: new Date(now).toISOString(),
      rate_limit: {
        primary_window: { used_percent: 58, reset_at: now + 2 * 60 * 60 * 1000 },
        secondary_window: { used_percent: 31, reset_at: now + 4 * 24 * 60 * 60 * 1000 },
      },
    }),
    session: {
      status: 'working',
      model: 'gpt-5.6-sol',
      label: '当前会话 · code #1',
      lastActivity: '刚刚更新',
      toolCalls: 4,
    },
    aiUsage: normalizeAiUsageSummary(aiUsageSummary),
    localUsage: normalizeLocalDailyRow(localDaily),
  };
}

export function formatCompactNumber(value) {
  const number = Number(value) || 0;
  if (Math.abs(number) >= 1_000_000_000) return `${(number / 1_000_000_000).toFixed(1)}B`;
  if (Math.abs(number) >= 1_000_000) return `${(number / 1_000_000).toFixed(1)}M`;
  if (Math.abs(number) >= 1_000) return `${(number / 1_000).toFixed(1)}K`;
  return number.toLocaleString('en-US');
}

export function formatCurrency(value) {
  return `$${(Number(value) || 0).toFixed(2)}`;
}

export function formatResetTime(iso) {
  if (!iso) return '等待同步';
  const remaining = Math.max(0, new Date(iso).getTime() - Date.now());
  const hours = Math.floor(remaining / 3_600_000);
  const minutes = Math.floor((remaining % 3_600_000) / 60_000);
  return hours > 0 ? `${hours}h ${minutes}m 后重置` : `${minutes}m 后重置`;
}
