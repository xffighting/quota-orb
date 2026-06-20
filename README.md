<div align="center">

# 🔮 Quota Orb

### Never waste your Claude & ChatGPT subscription quota again.

A tiny, glanceable floating orb for macOS that shows your **AI subscription limits** in real time — so you burn the quota you'd otherwise lose, and never hit the wall mid-task by surprise.

![Quota Orb](assets/hero.svg)

[![Platform](https://img.shields.io/badge/platform-macOS-black?logo=apple)](https://github.com/xffighting/quota-orb)
[![Language](https://img.shields.io/badge/Swift-AppKit-orange?logo=swift)](https://github.com/xffighting/quota-orb)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen)](https://github.com/xffighting/quota-orb/pulls)

</div>

---

## 💡 Why

You pay for Claude Pro/Max and ChatGPT/Codex. But:

- Quota resets every **5 hours** and every **week** — whatever you don't use just **evaporates**. 💸
- Or you're deep in a task and suddenly **hit the limit** with no warning.

Quota Orb puts both windows **on your screen, color-coded, always visible**. One glance tells you: *use it now, or save it for later, and which model still has room.*

## ✨ Features

- **Dual-ring orb per provider** — outer ring = 5-hour window, inner ring = weekly window.
- **Two countdowns, front and center** — color-matched to their rings. Know exactly when each resets.
- **"Use-it-or-lose-it" alert** — the orb breathes **red** when lots of quota is about to reset, **amber** when you're under-using. Don't waste what you paid for.
- **Click to jump** — click an orb to bring its app to front (Claude.app / Codex).
- **Hover for detail** — exact reset times, usage %, and a one-line verdict.
- **Official, real-time data** — read **100% locally**, costs **zero quota**.
- **Auto-start on login**, drag anywhere, remembers position.

## 🔒 Privacy first

This is the part that matters, because the tool reads your login state:

- It reads **only your own local login** (Claude desktop's keychain entry, Codex's local session files) **on your own machine**.
- It **sends nothing, anywhere**. No servers. No telemetry. No accounts.
- It **never spends quota** — it reads usage metadata and local files, not the model.
- It's **fully open source** — every line is right here. Read it before you run it.

## 🚀 Install

```bash
git clone https://github.com/xffighting/quota-orb.git
cd quota-orb
./install.sh
```

`install.sh` checks dependencies, compiles on **your** machine (so no Gatekeeper "unidentified developer" wall), sets up auto-start, and launches. Uninstall anytime with `./uninstall.sh`.

**Requirements:** macOS · [Node.js](https://nodejs.org) · Xcode Command Line Tools (`xcode-select --install`)

## 🧩 How it works

| Orb | Data source | Notes |
|-----|-------------|-------|
| **Claude** | Claude desktop login → official usage endpoint | Real-time. Needs Claude desktop signed in; otherwise falls back to a local-log estimate. |
| **ChatGPT** | Codex CLI's official `rate_limits` (written to local session files) | Official snapshot from your last Codex run. |

Each probe is a small, readable script (`*-probe.mjs` + `lib/*.py`). The orb itself is a single AppKit file (`QuotaOrb.swift`). Adding a provider is ~20 lines.

## 🗺️ Roadmap & contributing

PRs very welcome — some good first issues:

- [ ] **English UI** — the in-app labels are currently Chinese; i18n is a great first PR.
- [ ] More providers (Gemini, MiniMax, Cursor, …) — the architecture is provider-pluggable.
- [ ] Menu-bar mode as an alternative to the floating orb.
- [ ] Configurable thresholds & refresh interval via a settings file.

Found a bug or want a provider? [Open an issue](https://github.com/xffighting/quota-orb/issues).

## 📄 License

MIT — do whatever you like. If it saves you some quota, a ⭐ is appreciated.

<div align="center">
<sub>Built for people who hate watching paid quota expire.</sub>
</div>
