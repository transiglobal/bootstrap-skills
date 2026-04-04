#!/bin/bash
# OpenClaw 每日安全巡检脚本
# 巡检内容：SSH 失败登录、异常进程、磁盘/内存、监听端口、 systemd 失败服务
# 通知：飞书机器人 → OC_CRON_REPORT_TO（环境变量，部署时由 Agent 传入）

FEISHU_USER="${OC_CRON_REPORT_TO:-ou_01c2ea8bc1312dd73c93f1b972e5b021}"
FEISHU_APP_ID="cli_a940c6ac02785cd6"
FEISHU_APP_SECRET="wxSaKaCSrA1qsPRp47jgobEVKL6b13sP"
LOG_FILE="/root/.openclaw/workspace/scripts/security-audit.log"
LOCK_FILE="/tmp/security-audit.lock"

# 加锁防重复
exec 200>"$LOCK_FILE"
flock -n 200 || { echo "安全巡检已在运行中，退出"; exit 0; }

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }
send_feishu() {
  local title="$1"
  local content="$2"
  # 获取 tenant_access_token
  local TOKEN_RESP=$(curl -s -X POST "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal" \
    -H "Content-Type: application/json" \
    -d "{\"app_id\":\"$FEISHU_APP_ID\",\"app_secret\":\"$FEISHU_APP_SECRET\"}")
  local TOKEN=$(echo "$TOKEN_RESP" | python3 -c "import json,sys; print(json.load(sys.stdin).get('tenant_access_token',''))" 2>/dev/null)
  if [ -z "$TOKEN" ]; then
    log "[FEISHU] 获取 token 失败: $TOKEN_RESP"
    return 1
  fi
  # 发送富文本消息
  local PAYLOAD=$(python3 -c "
import json
msg = {
  'receive_id': '$FEISHU_USER',
  'msg_type': 'post',
  'content': json.dumps({
    'zh_cn': {
      'title': '$title',
      'content': [[{'tag': 'text', 'text': '$content'}]]
    }
  })
}
print(json.dumps(msg))
" 2>/dev/null)
  curl -s -X POST "https://open.feishu.cn/open-apis/im/v1/messages?receive_id_type=open_id" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" >> "$LOG_FILE" 2>&1
  log "[FEISHU] 消息已发送"
}

# ========== 巡检开始 ==========
START_TIME=$(date '+%Y-%m-%d %H:%M:%S')
log "========== 安全巡检开始 =========="

ISSUES=()
HOSTNAME=$(hostname)

# 1. SSH 失败登录（今日）
SSH_FAIL=$(grep -c "$(date '+%b %d')" /var/log/auth.log 2>/dev/null | tail -1 || echo "0")
if [ "$SSH_FAIL" -gt 10 ]; then
  ISSUES+=("⚠️ SSH 失败登录 $SSH_FAIL 次（今日），建议检查 /var/log/auth.log")
fi

# 2. 异常进程（CPU > 80% 或内存 > 90%）
HIGH_CPU=$(ps aux --sort=-%cpu | awk 'NR>1 && $3>80 {printf "%.1f%% CPU: %s (PID %s)\n", $3, $11, $2}' | head -5)
HIGH_MEM=$(ps aux --sort=-%mem | awk 'NR>1 && $4>90 {printf "%.1f%% MEM: %s (PID %s)\n", $4, $11, $2}' | head -5)
[ -n "$HIGH_CPU" ] && ISSUES+=("⚠️ 高CPU进程:\n$HIGH_CPU")
[ -n "$HIGH_MEM" ] && ISSUES+=("⚠️ 高内存进程:\n$HIGH_MEM")

# 3. 磁盘使用率
DISK_ISSUES=$(df -h | awk 'NR>1 && $5+0>85 {printf "%s 使用率 %s\n", $6, $5}' | head -5)
[ -n "$DISK_ISSUES" ] && ISSUES+=("⚠️ 磁盘使用率 > 85%:\n$DISK_ISSUES")

# 4. 内存使用率
MEM_PCT=$(free | awk '/Mem:/ {printf "%.0f", $3/$2 * 100}')
if [ "$MEM_PCT" -gt 90 ]; then
  ISSUES+=("⚠️ 内存使用率 ${MEM_PCT}%（> 90%）")
fi

# 5. 监听端口异常（排除常见端口）
UNEXPECTED_PORTS=$(ss -tlnp 2>/dev/null | awk 'NR>1 {split($4,a,":"); port=a[length(a)]; if(port>30000 && port<60000) print port}' | sort -u | head -10)
[ -n "$UNEXPECTED_PORTS" ] && ISSUES+=("⚠️ 非标准高位端口监听:\n$UNEXPECTED_PORTS")

# 6. systemd 失败服务
FAILED_SVCS=$(systemctl list-units --failed --no-legend 2>/dev/null | awk '{print $1}' | grep -v "^$" | head -5)
[ -n "$FAILED_SVCS" ] && ISSUES+=("⚠️ systemd 失败服务:\n$FAILED_SVCS")

# 7. 安全更新可用
SEC_UPDATES=$(apt list --upgradable 2>/dev/null | grep -i security | wc -l)
[ "$SEC_UPDATES" -gt 0 ] && ISSUES+=("🔒 有 $SEC_UPDATES 个安全更新可用（apt upgrade）")

# ========== 生成报告 ==========
if [ ${#ISSUES[@]} -eq 0 ]; then
  SUMMARY="✅ 安全巡检通过\n📅 $START_TIME\n🖥️ $HOSTNAME\n🔎 巡检项：SSH/进程/磁盘/内存/端口/服务/安全更新\n\n所有检查项正常，无异常发现。"
  send_feishu "🛡️ 安全巡检报告 - $HOSTNAME" "$SUMMARY"
else
  SUMMARY="⚠️ 安全巡检发现 ${#ISSUES[@]} 项问题\n📅 $START_TIME\n🖥️ $HOSTNAME"
  SUMMARY="$SUMMARY\n━━━━━━━━━━━━━━━"
  for issue in "${ISSUES[@]}"; do
    SUMMARY="$SUMMARY\n$issue"
  done
  send_feishu "⚠️ 安全巡检报告 - $HOSTNAME" "$SUMMARY"
fi

log "========== 安全巡检完成 =========="
exit 0
