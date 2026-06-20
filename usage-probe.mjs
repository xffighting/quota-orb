#!/usr/bin/env node
// 读取本地 Claude Code 会话日志，输出当前 5 小时窗口与近 7 天的用量估算 JSON。
// 百分比基准 = 历史最高消耗（成本加权），非官方额度。
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

const round1 = (x) => Math.round(x * 10) / 10;

// 官方数据源：调 lib/fetch-official.py（解密桌面版 sessionKey → claude.ai usage 接口）。
// sessionKey 由桌面版自动续期，故零额度、零干预、自动保鲜。任何异常返回 null，回退到本地估算。
const FETCH_OFFICIAL = new URL('./lib/fetch-official.py', import.meta.url).pathname;

function officialUsage() {
  for (const py of ['python3', '/usr/bin/python3']) {
    try {
      const out = execFileSync(py, [FETCH_OFFICIAL], {
        encoding: 'utf8',
        timeout: 30000,
        stdio: ['ignore', 'pipe', 'ignore'],
      });
      const j = JSON.parse(out);
      if (j?.five && typeof j.five.pct === 'number') return j;
    } catch {}
  }
  return null;
}

const official = officialUsage();
if (official) {
  console.log(JSON.stringify(official));
  process.exit(0);
}

const CCUSAGE_CANDIDATES = ['ccusage'];

function runCcusage(args) {
  for (const bin of CCUSAGE_CANDIDATES) {
    try {
      const out = execFileSync(bin, ['claude', ...args, '--json', '--offline'], {
        encoding: 'utf8',
        maxBuffer: 256 * 1024 * 1024,
        stdio: ['ignore', 'pipe', 'ignore'],
      });
      return JSON.parse(out);
    } catch {}
  }
  try {
    const out = execFileSync('npx', ['-y', 'ccusage@latest', 'claude', ...args, '--json'], {
      encoding: 'utf8',
      maxBuffer: 256 * 1024 * 1024,
      stdio: ['ignore', 'pipe', 'ignore'],
    });
    return JSON.parse(out);
  } catch {}
  return null;
}

// 手动校准（可选）：~/.config/quota-orb/calibration.json
// 例 {"fiveLimitUSD": 50, "weekLimitUSD": 120}，由官方 /usage 百分比反推得出。
let calib = {};
try {
  calib = JSON.parse(readFileSync(`${process.env.HOME}/.config/quota-orb/calibration.json`, 'utf8'));
} catch {}

// —— 5 小时窗口 ——
const bj = runCcusage(['blocks']);
const blocks = (bj?.blocks ?? []).filter((b) => !b.isGap);
const active = blocks.find((b) => b.isActive) ?? null;
const histMaxBlock = Math.max(
  0.01,
  ...blocks.filter((b) => !b.isActive).map((b) => b.costUSD ?? 0)
);
const fiveCost = active?.costUSD ?? 0;
const fiveLimit = calib.fiveLimitUSD
  ? Math.max(calib.fiveLimitUSD, fiveCost)
  : Math.max(histMaxBlock, fiveCost);
const five = {
  pct: round1((fiveCost / fiveLimit) * 100),
  cost: round1(fiveCost),
  limit: round1(fiveLimit),
  resetAt: active?.endTime ?? null,
  startAt: active?.startTime ?? null,
};

// —— 近 7 天滚动窗口 ——
const dj = runCcusage(['daily']);
const days = (dj?.daily ?? [])
  .map((d) => ({ date: d.period ?? d.date, cost: d.totalCost ?? d.costUSD ?? 0 }))
  .filter((d) => typeof d.date === 'string')
  .sort((a, b) => a.date.localeCompare(b.date));

const costByDate = new Map(days.map((d) => [d.date, d.cost]));
let weekCost = 0;
let weekMax = 0.01;
if (days.length > 0) {
  const dayMs = 86400000;
  const first = new Date(days[0].date + 'T00:00:00');
  const today = new Date();
  const fmt = (t) => {
    const d = new Date(t);
    const p = (n) => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
  };
  const win = [];
  for (let t = first.getTime(); t <= today.getTime(); t += dayMs) {
    win.push(costByDate.get(fmt(t)) ?? 0);
    if (win.length > 7) win.shift();
    const s = win.reduce((a, b) => a + b, 0);
    if (s > weekMax) weekMax = s;
    weekCost = s;
  }
}
const weekLimit = calib.weekLimitUSD ? Math.max(calib.weekLimitUSD, weekCost) : weekMax;
// 周重置：以校准锚点为基准，按 7 天周期滚动到下一个重置时刻。
let weekResetAt = null;
if (calib.weekAnchorMs) {
  const wk = 7 * 86400000;
  let next = calib.weekAnchorMs;
  const now = Date.now();
  if (next <= now) next += Math.ceil((now - next) / wk) * wk;
  weekResetAt = new Date(next).toISOString();
}
const week = {
  pct: round1((weekCost / weekLimit) * 100),
  cost: round1(weekCost),
  limit: round1(weekLimit),
  resetAt: weekResetAt,
};

console.log(JSON.stringify({ five, week, source: 'estimate', at: new Date().toISOString() }));
