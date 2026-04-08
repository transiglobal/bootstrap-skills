#!/bin/bash
# OpenClaw 每日系统更新脚本
# 自动升级系统包，报告升级结果

REPORT_DIR="/tmp/openclaw/security-reports"
TIMESTAMP=$(date +%Y-%m-%d)
REPORT_FILE="$REPORT_DIR/os-upgrade-$TIMESTAMP.txt"

mkdir -p "$REPORT_DIR"

# 报告头
cat > "$REPORT_FILE" << 'EOF'
🖥️ OpenClaw 每日系统更新报告
========================================
EOF

echo "执行时间: $(date '+%Y-%m-%d %H:%M:%S %Z')" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# 执行升级
echo "=== 开始升级 ===" >> "$REPORT_FILE"
UPGRADE_LOG="/tmp/openclaw/apt-upgrade-$TIMESTAMP.log"

if sudo /usr/bin/apt update >> "$UPGRADE_LOG" 2>&1 && \
   sudo /usr/bin/apt upgrade -y >> "$UPGRADE_LOG" 2>&1; then
    echo "✅ apt upgrade 成功" >> "$REPORT_FILE"
else
    echo "⚠️ apt upgrade 失败，详见日志" >> "$REPORT_FILE"
fi

# 自动清理
sudo /usr/bin/apt autoremove -y >> "$UPGRADE_LOG" 2>&1 || true

echo "" >> "$REPORT_FILE"

# 记录本次升级了哪些包
echo "=== 本次升级的包 ===" >> "$REPORT_FILE"
if [ -f /var/log/apt/history.log ]; then
    TODAY=$(date +%Y-%m-%d)
    grep -A20 "Start-Date: $TODAY" /var/log/apt/history.log 2>/dev/null | \
        grep "^Upgrade:" >> "$REPORT_FILE" || echo "无包被升级" >> "$REPORT_FILE"
fi

echo "" >> "$REPORT_FILE"
echo "=== 报告生成完成 ===" >> "$REPORT_FILE"

# 【简报推送】直接输出详细日志文件内容（完整信息，不过滤）
cat "$REPORT_FILE"
