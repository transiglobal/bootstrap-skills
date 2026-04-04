#!/bin/bash
# OpenClaw 每日系统升级巡检脚本
# 巡检内容：可更新包、安全更新、内核升级、系统负载
# 通知：飞书机器人 → OC_CRON_REPORT_TO（环境变量，部署时由 Agent 传入）

FEISHU_USER="${OC_CRON_REPORT_TO:-ou_01c2ea8bc1312dd73c93f1b972e5b021}"
FEISHU_APP_ID="cli_a940c6ac02785cd6"
FEISHU_APP_SECRET="wxSaKaCSrA1qsPRp47jgobEVKL6b13sP"
LOG_FILE="/root/.openclaw/workspace/scripts/os-upgrade.log"
LOCK_FILE="/tmp/os-upgrade.lock"

# 加锁防重复
exec 200>"$LOCK_FILE"
flock -n 200 || { echo "系统升级巡检已在运行中，退出"; exit 0; }

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }
send_feishu() {
  local title="$1"
  local content="$2"
  local TOKEN_RESP=$(curl -s -X POST "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal" \
    -H "Content-Type: application/json" \
    -d "{\"app_id\":\"$FEISHU_APP_ID\",\"app_secret\":\"$FEISHU_APP_SECRET\"}")
  local TOKEN=$(echo "$TOKEN_RESP" | python3 -c "import json,sys; print(json.load(sys.stdin).get('tenant_access_token',''))" 2>/dev/null)
  if [ -z "$TOKEN" ]; then
    log "[FEISHU] 获取 token 失败"
    return 1
  fi
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
HOSTNAME=$(hostname)
log "========== 系统升级巡检开始 =========="

ISSUES=()
UPDATES=()

# 1. 更新包列表
apt-get update -qq 2>>"$LOG_FILE"
UPGRADABLE=$(apt list --upgradable 2>/dev/null | tail -n +2)
TOTAL=$(echo "$UPGRADABLE" | wc -l | tr -d ' ')
SEC_UPDATES=$(echo "$UPGRADABLE" | grep -ci security || echo "0")

if [ "$TOTAL" -gt 0 ]; then
  UPDATES+=("📦 共 $TOTAL 个包可更新，其中 $SEC_UPDATES 个安全更新")
  # 只列出前10个重要的
  TOP_UPDATES=$(echo "$UPGRADABLE" | head -10 | cut -d'/' -f1 | paste -sd', ')
  [ -n "$TOP_UPDATES" ] && UPDATES+=("热门: $TOP_UPDATES")
else
  UPDATES+=("✅ 系统已是最新状态，无可用更新")
fi

# 2. 内核升级
KERNEL_CURRENT=$(uname -r)
KERNEL_LATEST=$(dpkg -l linux-image-* 2>/dev/null | awk '/^ii/ {print $3}' | sort -V | tail -1)
if [ "$KERNEL_LATEST" != "$KERNEL_CURRENT" ]; then
  ISSUES+=("🔴 内核可升级: ${KERNEL_CURRENT} → ${KERNEL_LATEST}")
fi

# 3. 系统负载
LOAD=$(uptime | awk -F'load average:' '{print $2}')
UPDATA=$(echo "$LOAD" | awk '{print $1}' | tr -d ',')
CORES=$(nproc)
LOAD_PCT=$(python3 -c "print(int($UPDATA / $CORES * 100))" 2>/dev/null || echo "0")
if [ "$LOAD_PCT" -gt 80 ]; then
  ISSUES+=("⚠️ 系统负载过高: $LOAD（Cores: $CORES）")
fi

# 4. 重启必要性检查
NEEDS_REBOOT=""
if [ -f /var/run/reboot-required ]; then
  NEEDS_REBOOT="🔴 系统需要重启（/var/run/reboot-required 存在）"
elif [ "$KERNEL_LATEST" != "$KERNEL_CURRENT" ]; then
  NEEDS_REBOOT="🟡 内核已更新，需要重启生效"
fi
[ -n "$NEEDS_REBOOT" ] && ISSUES+=("$NEEDS_REBOOT")

# ========== 生成报告 ==========
SUMMARY="📊 系统升级巡检报告\n📅 $START_TIME\n🖥️ $HOSTNAME\n━━━━━━━━━━━━━━━"

if [ ${#UPDATES[@]} -gt 0 ]; then
  for u in "${UPDATES[@]}"; do
    SUMMARY="$SUMMARY\n$u"
  done
fi
if [ ${#ISSUES[@]} -gt 0 ]; then
  SUMMARY="$SUMMARY\n━━━ 需关注 ━━━"
  for i in "${ISSUES[@]}"; do
    SUMMARY="$SUMMARY\n$i"
  done
fi

send_feishu "📊 系统升级巡检 - $HOSTNAME" "$SUMMARY"
log "========== 系统升级巡检完成 =========="
exit 0
