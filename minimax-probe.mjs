#!/usr/bin/env node
// MiniMax Coding Plan 用量探针。优先官方（Chrome 登录态读月度信用点），失败回退本地估算/未配置。
import { execFileSync } from 'node:child_process';
import { existsSync } from 'node:fs';

// 优先官方：用 Chrome 里 minimax.io 登录态读月度信用点额度。
const FETCH_OFFICIAL = new URL('./lib/fetch-minimax.py', import.meta.url).pathname;
try {
  const out = execFileSync('python3', [FETCH_OFFICIAL], {
    encoding: 'utf8', timeout: 30000, stdio: ['ignore', 'pipe', 'ignore'],
  });
  const j = JSON.parse(out);
  if (j?.source === 'minimax-official') { console.log(out.trim()); process.exit(0); }
} catch {}

const CONFIG_DIR = `${process.env.HOME}/.claude-minimax`;
const CCUSAGE = ['ccusage'];
const round1 = (x) => Math.round(x * 10) / 10;

function ccusage(args) {
  for (const bin of CCUSAGE) {
    try {
      const out = execFileSync(bin, ['claude', ...args, '--json', '--offline'], {
        encoding: 'utf8',
        maxBuffer: 256 * 1024 * 1024,
        stdio: ['ignore', 'pipe', 'ignore'],
        env: { ...process.env, CLAUDE_CONFIG_DIR: CONFIG_DIR },
      });
      return JSON.parse(out);
    } catch {}
  }
  return null;
}

const empty = { five: { pct: 0, resetAt: null }, week: { pct: 0, resetAt: null }, source: 'minimax-none', at: new Date().toISOString() };

if (!existsSync(`${CONFIG_DIR}/projects`)) {
  console.log(JSON.stringify(empty));
  process.exit(0);
}

const bj = ccusage(['blocks']);
const blocks = (bj?.blocks ?? []).filter((b) => !b.isGap);
if (blocks.length === 0) {
  console.log(JSON.stringify(empty));
  process.exit(0);
}

const active = blocks.find((b) => b.isActive) ?? null;
const histMax = Math.max(0.01, ...blocks.filter((b) => !b.isActive).map((b) => b.costUSD ?? 0));
const fiveCost = active?.costUSD ?? 0;
const fiveLimit = Math.max(histMax, fiveCost);

const dj = ccusage(['daily']);
const days = (dj?.daily ?? [])
  .map((d) => ({ date: d.period ?? d.date, cost: d.totalCost ?? d.costUSD ?? 0 }))
  .filter((d) => typeof d.date === 'string')
  .sort((a, b) => a.date.localeCompare(b.date));
const costByDate = new Map(days.map((d) => [d.date, d.cost]));
let weekCost = 0, weekMax = 0.01;
if (days.length) {
  const dayMs = 86400000, p = (n) => String(n).padStart(2, '0');
  const fmt = (t) => { const d = new Date(t); return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`; };
  const first = new Date(days[0].date + 'T00:00:00'), today = new Date(), win = [];
  for (let t = first.getTime(); t <= today.getTime(); t += dayMs) {
    win.push(costByDate.get(fmt(t)) ?? 0);
    if (win.length > 7) win.shift();
    const s = win.reduce((a, b) => a + b, 0);
    if (s > weekMax) weekMax = s;
    weekCost = s;
  }
}

console.log(JSON.stringify({
  five: { pct: round1((fiveCost / fiveLimit) * 100), resetAt: active?.endTime ?? null },
  week: { pct: round1((weekCost / weekMax) * 100), resetAt: null },
  source: 'estimate',
  at: new Date().toISOString(),
}));
