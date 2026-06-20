#!/usr/bin/env node
// 读取 Codex CLI 最近会话文件里的官方 rate_limits（ChatGPT 额度），输出与 Claude 探针一致的 JSON。
// primary = 5 小时窗口(window_minutes:300)，secondary = 周窗口(10080)。
// 数据新鲜度 = 你上次跑 Codex 的时刻（会话文件 mtime），跑一次 Codex 即刷新。
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

const SESSIONS_DIR = `${process.env.HOME}/.codex/sessions`;
const round1 = (x) => Math.round(x * 10) / 10;

function listSessionFiles(dir) {
  const out = [];
  let entries;
  try { entries = readdirSync(dir, { withFileTypes: true }); } catch { return out; }
  for (const e of entries) {
    const p = join(dir, e.name);
    if (e.isDirectory()) out.push(...listSessionFiles(p));
    else if (e.name.endsWith('.jsonl')) out.push(p);
  }
  return out;
}

function findRateLimits(obj) {
  if (obj && typeof obj === 'object') {
    if (obj.rate_limits) return obj.rate_limits;
    for (const v of Array.isArray(obj) ? obj : Object.values(obj)) {
      const r = findRateLimits(v);
      if (r) return r;
    }
  }
  return null;
}

function lastRateLimits(file) {
  const lines = readFileSync(file, 'utf8').split('\n');
  for (let i = lines.length - 1; i >= 0; i--) {
    if (!lines[i].includes('"rate_limits"')) continue;
    try {
      const rl = findRateLimits(JSON.parse(lines[i]));
      if (rl && (rl.primary || rl.secondary)) return rl;
    } catch {}
  }
  return null;
}

const files = listSessionFiles(SESSIONS_DIR)
  .map((f) => ({ f, m: statSync(f).mtimeMs }))
  .sort((a, b) => b.m - a.m);

let rl = null, mtime = null;
for (const { f, m } of files) {
  rl = lastRateLimits(f);
  if (rl) { mtime = m; break; }
}

if (!rl) {
  console.log(JSON.stringify({ five: { pct: 0, resetAt: null }, week: { pct: 0, resetAt: null }, source: 'codex-none', at: new Date().toISOString() }));
  process.exit(0);
}

const isoFrom = (sec) => (sec ? new Date(sec * 1000).toISOString() : null);
const p = rl.primary || {};
const s = rl.secondary || {};

console.log(JSON.stringify({
  five: { pct: round1(p.used_percent ?? 0), cost: 0, limit: 0, resetAt: isoFrom(p.resets_at), startAt: null },
  week: { pct: round1(s.used_percent ?? 0), cost: 0, limit: 0, resetAt: isoFrom(s.resets_at) },
  source: 'codex-official',
  dataAge: mtime ? Math.round((Date.now() - mtime) / 60000) : null,
  at: new Date().toISOString(),
}));
