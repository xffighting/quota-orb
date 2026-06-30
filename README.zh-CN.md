<div align="center">

# 🔮 Quota Orb

### 花钱买的 AI 额度，别再让它白白蒸发。

macOS 上几颗晶莹的悬浮球，实时显示 **Claude · ChatGPT · MiniMax** 的额度——把不用就过期的额度用起来，也不再干到一半突然撞限额。

![Quota Orb](assets/hero.svg)

[![Platform](https://img.shields.io/badge/platform-macOS-black?logo=apple)](https://github.com/xffighting/quota-orb)
[![Swift](https://img.shields.io/badge/Swift-AppKit-orange?logo=swift)](https://github.com/xffighting/quota-orb)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen)](https://github.com/xffighting/quota-orb/pulls)
[![Stars](https://img.shields.io/github/stars/xffighting/quota-orb?style=social)](https://github.com/xffighting/quota-orb/stargazers)

[English](README.md) · **中文**

</div>

---

## 💸 痛点

你开了 Claude Pro/Max、ChatGPT/Codex、MiniMax Coding Plan。可是：

- 额度每 **5 小时**、每 **周** 重置，**没用掉的就蒸发了**；
- 或者正干在兴头上，**毫无预警地撞到限额**。

要么**白白浪费钱**，要么**被突然卡住**。Quota Orb 两个都治。

## ✨ 它能做什么

每家一颗玻璃小球，常驻屏幕、颜色编码，瞄一眼全知道：

- 🔵 **双环** —— 外环 = 5 小时窗口，内环 = 周窗口，各带实时重置倒计时。
- 🔴 **「用不完就浪费」提醒** —— 大量额度即将重置时球**呼吸变红**，用得太慢时变**琥珀**。别浪费付过钱的额度。
- 🧲 **三球联动** —— 拖任意一颗，三颗一起动。贴到左右边自动**竖排**，贴到上下边自动**横排**。
- 💎 **水晶质感** —— 磨砂玻璃珠 + 柔光高光，常驻屏幕也好看。
- 🖱️ **点击直达** 对应应用（Claude.app / Codex）；**悬停**看精确重置时间和一句话建议。
- 🖥️ **多屏稳定** —— 跨屏吸附、隐藏、找回都正确。球丢了？右键 → **找回所有球**。
- 🌍 **双语**（按系统语言自动中/英）· **开机自启**。

## 🔒 隐私 —— 看完就放心

工具要读你的登录态，把话说清楚：

- ✅ **只读你自己机器上、你自己的本地登录态**（Claude 桌面版钥匙串、Codex 本地会话文件、浏览器里的 MiniMax cookie）。
- ✅ **不向任何地方发送任何东西**。没有服务器、没有埋点、不需要账号。
- ✅ **从不消耗额度** —— 读的是用量元数据和本地文件，不调用模型。
- ✅ **完全开源** —— 每一行都在这里，跑之前可以自己审。
- ✅ **本机编译** —— 不是别人签名的二进制，没有「身份不明的开发者」拦截。

## 🚀 安装（一行命令）

```bash
git clone https://github.com/xffighting/quota-orb.git
cd quota-orb && ./install.sh
```

`install.sh` 自动检查依赖、在**你自己机器上**编译、设好开机自启并启动。随时 `./uninstall.sh` 卸载。

**环境要求：** macOS · [Node.js](https://nodejs.org) · Xcode 命令行工具（`xcode-select --install`）

## 🧩 工作原理

| 球 | 数据源 | 说明 |
|----|--------|------|
| **Claude** | Claude 桌面版登录态 → 官方用量接口 | 实时。未登录则退回本地日志估算。 |
| **ChatGPT** | Codex CLI 本地会话文件里的官方 `rate_limits` | 你上次跑 Codex 时的官方快照。 |
| **MiniMax** | 浏览器登录态 → Coding Plan 接口 | 读 5 小时窗口，周窗口无限显示 ∞。需 MiniMax coding plan + 浏览器登录。 |

每个探针都是一小段可读脚本，悬浮球本体是单个 AppKit 文件。新增一家约 20 行——**欢迎 PR 加更多 provider。**

## 🗺️ 路线图

- [x] 双语 UI（中 / 英）
- [x] 三球联动 + 横竖排自动布局
- [x] 多屏稳定
- [ ] 更多 provider（Gemini、Cursor、Copilot…）
- [ ] 菜单栏模式
- [ ] 更多语言（日本語、Español…）

发现 bug 或想加某家？[提个 issue](https://github.com/xffighting/quota-orb/issues)。

## ⭐ 喜欢的话

如果 Quota Orb 帮你省下哪怕一次浪费的额度、躲过一次突然的限额，**点个 star** 吧——这是本项目唯一的「额度」，也能帮更多人发现它。

## 📄 许可

MIT，随便用。

<div align="center">
<sub>献给见不得花钱买的额度白白过期的人。</sub>
</div>
