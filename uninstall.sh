#!/bin/zsh
# 卸载 Quota Orb：停止 + 取消开机自启。（不会删源文件夹，自己删即可）
LABEL="com.quota-orb.app"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
launchctl unload "$PLIST" 2>/dev/null || true
rm -f "$PLIST"
pkill -f "quota-orb/quota-orb" 2>/dev/null || true
echo "✓ 已停止并取消开机自启。源文件夹可自行删除。"
echo "  （额度数据是实时读取的，没有缓存残留；本工具从未上传任何数据）"
