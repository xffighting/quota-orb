<div align="center">

# 🔮 Quota Orb

### You pay for AI. Stop letting the quota evaporate.

Tiny, glassy floating orbs for macOS that show your **Claude · ChatGPT · MiniMax** limits in real time — so you spend the quota you'd otherwise waste, and never slam into the wall mid-task again.

![Quota Orb](assets/hero.svg)

[![Platform](https://img.shields.io/badge/platform-macOS-black?logo=apple)](https://github.com/xffighting/quota-orb)
[![Swift](https://img.shields.io/badge/Swift-AppKit-orange?logo=swift)](https://github.com/xffighting/quota-orb)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen)](https://github.com/xffighting/quota-orb/pulls)
[![Stars](https://img.shields.io/github/stars/xffighting/quota-orb?style=social)](https://github.com/xffighting/quota-orb/stargazers)

**English** · [中文](README.zh-CN.md)

</div>

---

## 💸 The problem

You're paying for Claude Pro/Max, ChatGPT/Codex, a MiniMax coding plan. But:

- Quota resets every **5 hours** and every **week** — whatever you don't use just **vanishes**.
- Or you're deep in a flow and **hit the limit with zero warning**.

You're either **leaving money on the table** or **getting blindsided**. Quota Orb fixes both.

## ✨ What it does

A small glass orb per provider, always on screen, color-coded so a single glance tells you everything:

- 🔵 **Dual rings** — outer = 5-hour window, inner = weekly window, each with its own live reset countdown.
- 🔴 **Use-it-or-lose-it alerts** — the orb **breathes red** when lots of quota is about to reset, **amber** when you're under-using. Never waste what you paid for.
- 🧲 **Move as a group** — drag any orb and all three follow. Snap to a side → they stack vertically; snap to top/bottom → they line up horizontally. Auto-arranged.
- 💎 **Crystal UI** — frosted-glass spheres with a soft glow. Pretty enough to keep on screen all day.
- 🖱️ **Click to jump** to the matching app (Claude.app / Codex); **hover** for exact reset times and a one-line verdict.
- 🖥️ **Multi-monitor safe** — snaps, hides, and recovers correctly across displays. Lost an orb? Right-click → **Show all orbs**.
- 🌍 **Bilingual** (English / 中文, auto by system language) · **auto-start on login**.

## 🔒 Privacy — read this, then trust it

The tool reads your login state, so here's exactly what it does and doesn't do:

- ✅ Reads **only your own local login** (Claude desktop's keychain entry, Codex's local session files, your browser's MiniMax cookie) — **on your machine, for your account.**
- ✅ **Sends nothing, anywhere.** No servers. No telemetry. No account.
- ✅ **Costs zero quota** — it reads usage metadata and local files, never the model.
- ✅ **Fully open source** — every line is right here. Read it before you run it.
- ✅ **Builds locally** — no signed binary, no "unidentified developer" wall, nothing you can't inspect.

## 🚀 Install (one command)

```bash
git clone https://github.com/xffighting/quota-orb.git
cd quota-orb && ./install.sh
```

`install.sh` checks deps, compiles **on your machine**, sets up auto-start, and launches. Uninstall anytime with `./uninstall.sh`.

**Requirements:** macOS · [Node.js](https://nodejs.org) · Xcode Command Line Tools (`xcode-select --install`)

## 🧩 How it works

| Orb | Source | Notes |
|-----|--------|-------|
| **Claude** | Claude desktop login → official usage endpoint | Real-time. Falls back to a local-log estimate if not signed in. |
| **ChatGPT** | Codex CLI's official `rate_limits` (local session files) | Official snapshot from your last Codex run. |
| **MiniMax** | MiniMax coding-plan API via your browser session | Reads the 5-hour window; weekly shows ∞ (unlimited). Needs a MiniMax coding plan + browser login. |

Each probe is a small, readable script. The orb itself is a single AppKit file. Adding a provider is ~20 lines — **PRs for new providers are very welcome.**

## 🗺️ Roadmap

- [x] Bilingual UI (English / 中文)
- [x] Group movement + auto horizontal/vertical layout
- [x] Multi-monitor robustness
- [ ] More providers (Gemini, Cursor, Copilot…) — the architecture is provider-pluggable
- [ ] Menu-bar mode
- [ ] More languages (日本語, Español…)

Found a bug or want a provider? [Open an issue](https://github.com/xffighting/quota-orb/issues).

## ⭐ Like it?

If Quota Orb saves you from one wasted reset or one surprise limit, **drop a star** — it's the only "quota" this project runs on, and it helps other people find it.

## 📄 License

MIT — do whatever you like.

<div align="center">
<sub>Built for people who hate watching paid quota expire.</sub>
</div>
