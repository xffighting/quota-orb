#!/bin/zsh
# Quota Orb 一键安装：编译 + 依赖 + 开机自启。在解压后的文件夹里运行：  ./install.sh
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
LABEL="com.quota-orb.app"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

echo "▶ Quota Orb 安装到：$DIR"

# 1. 依赖检查
miss=0
command -v swiftc >/dev/null 2>&1 || { echo "  ✗ 缺 Xcode 命令行工具 → 运行：xcode-select --install"; miss=1; }
command -v node   >/dev/null 2>&1 || { echo "  ✗ 缺 node → 装：brew install node  或  https://nodejs.org"; miss=1; }
command -v python3 >/dev/null 2>&1 || { echo "  ✗ 缺 python3（macOS 一般自带，或 brew install python）"; miss=1; }
[ "$miss" = 1 ] && { echo "请先装好上面缺的依赖再重跑。"; exit 1; }

# 2. MiniMax 官方额度需要 curl_cffi（缺了不影响 Claude/ChatGPT）
if ! python3 -c "import curl_cffi" >/dev/null 2>&1; then
  echo "▶ 安装 curl_cffi（MiniMax 官方额度用）…"
  pip3 install --user --quiet curl_cffi 2>/dev/null || echo "  ⚠ curl_cffi 安装失败，MiniMax 官方额度将不可用（其它两个不受影响）"
fi

# 3. 编译
echo "▶ 编译中…"
swiftc -O "$DIR/QuotaOrb.swift" -o "$DIR/quota-orb"

# 4. 写 LaunchAgent（开机自启 + 崩溃自动拉起；手动退出不拉起）
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key><array><string>$DIR/quota-orb</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
    <key>ProcessType</key><string>Interactive</string>
    <key>StandardOutPath</key><string>$DIR/orb.log</string>
    <key>StandardErrorPath</key><string>$DIR/orb.log</string>
</dict>
</plist>
EOF

# 5. 启动
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
sleep 3

if pgrep -f "$DIR/quota-orb" >/dev/null; then
  echo "✓ 完成！三个额度球已在屏幕右上角启动，并设为开机自启。"
  echo "  · 拖动换位置 · 悬停看详情 · 右键菜单：刷新 / 退出"
  echo "  · 卸载：运行  ./uninstall.sh"
else
  echo "⚠ 进程没起来，看日志：$DIR/orb.log"
fi
