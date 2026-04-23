#!/bin/bash
set -uo pipefail

# 脚本自身所在目录（用于访问同目录下的完整脚本文件）
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 颜色定义
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'

# 辅助函数
log()    { echo -e "${GREEN}[✓]${NC} $1"; }
warn()   { echo -e "${YELLOW}[!]${NC} $1"; }
fail()   { echo -e "${RED}[✗]${NC} $1"; exit 1; }
info()   { echo -e "${BLUE}[i]${NC} $1"; }
prompt() { echo -e "${YELLOW}[?]${NC} $1"; }

# ── 安装模式（由调用方通过环境变量传入）───────────────
# OC_INSTALL_MODE=local | remote（由 Agent 在调用前设置）
if [ -z "${OC_INSTALL_MODE:-}" ]; then
  warn "OC_INSTALL_MODE 未设置，默认为 local"
  OC_INSTALL_MODE="local"
fi
info "安装模式：${OC_INSTALL_MODE}"

# 统计变量
SUCCESS=0
SKIPPED=0
FAILED=0

# ============================================================
# 阶段 0：依赖检查与安装
# ============================================================
info "阶段 0：检查依赖..."

check_and_install() {
  local cmd=$1
  local pkg=$2
  if command -v "$cmd" &>/dev/null; then
    log "$cmd 已安装"
    return 0
  fi
  warn "$cmd 未安装，正在安装 $pkg..."
  if sudo apt install -y "$pkg" &>/dev/null 2>&1; then
    log "$pkg 安装成功"
  else
    # apt 源失败时尝试从 archive.ubuntu.com 下载 deb
    warn "apt 安装失败，尝试从 Ubuntu 官方源下载..."
    local DEB_FILE="/tmp/${pkg}.deb"
    local DEB_URL=""
    case "$pkg" in
      inotify-tools)
        # 先安装依赖 libinotifytools0
        local DEP_FILE="/tmp/libinotifytools0.deb"
        curl -fsSL "http://archive.ubuntu.com/ubuntu/pool/universe/i/inotify-tools/libinotifytools0_3.22.6.0-4_amd64.deb" -o "$DEP_FILE" 2>/dev/null && \
          sudo dpkg -i "$DEP_FILE" &>/dev/null && rm -f "$DEP_FILE"
        DEB_URL="http://archive.ubuntu.com/ubuntu/pool/universe/i/inotify-tools/inotify-tools_3.22.6.0-4_amd64.deb"
        ;;
      git-crypt)
        DEB_URL="http://archive.ubuntu.com/ubuntu/pool/universe/g/git-crypt/git-crypt_0.7.0-0.1build3_amd64.deb"
        ;;
    esac
    if [ -n "$DEB_URL" ] && curl -fsSL "$DEB_URL" -o "$DEB_FILE" 2>/dev/null && sudo dpkg -i "$DEB_FILE" &>/dev/null; then
      rm -f "$DEB_FILE"
      log "$pkg 安装成功（备用源）"
    else
      fail "$pkg 安装失败，请手动安装后重试"
    fi
  fi
}

check_and_install git git
check_and_install gpg gnupg
check_and_install inotifywait inotify-tools

# git-crypt 特殊处理
if ! command -v git-crypt &>/dev/null; then
  warn "git-crypt 未安装，尝试从 apt 安装..."
  if sudo apt install -y git-crypt &>/dev/null; then
    log "git-crypt 安装成功"
  else
    warn "apt 安装失败，尝试从 Ubuntu 源下载..."
    DEB_URL="http://archive.ubuntu.com/ubuntu/pool/universe/g/git-crypt/git-crypt_0.7.0-0.1build3_amd64.deb"
    DEB_FILE="/tmp/git-crypt.deb"
    if curl -fsSL "$DEB_URL" -o "$DEB_FILE" && sudo dpkg -i "$DEB_FILE"; then
      log "git-crypt 安装成功"
      rm -f "$DEB_FILE"
    else
      fail "git-crypt 安装失败"
    fi
  fi
else
  log "git-crypt 已安装"
fi

# ============================================================
# 阶段 1：技能安装（含重复检测）
# ============================================================
info "阶段 1：技能安装..."

# 提示输入 Token A（支持环境变量 OC_TOKEN_A 非交互传入）
info "即将从 git.moguyn.cn 私有库下载技能"
if [ -n "${OC_TOKEN_A:-}" ]; then
  TOKEN_A="$OC_TOKEN_A"
  info "使用环境变量 OC_TOKEN_A 提供的技能下载 Token"
else
  info "需要传米科技提供的技能下载 Token（仅用于本次下载，不会保存到任何地方）"
  prompt "请输入技能下载 Token："
  read -rs TOKEN_A < /dev/tty
  echo
fi

if [ -z "$TOKEN_A" ]; then
  warn "未提供 Token，跳过技能安装阶段"
else
  # 动态获取 Gitea 命名空间（优先环境变量，否则通过 API 获取当前 token 用户名）
  if [ -n "${GITEA_NAMESPACE:-}" ]; then
    info "使用环境变量 GITEA_NAMESPACE=${GITEA_NAMESPACE}"
  elif [ -n "$TOKEN_A" ]; then
    GITEA_NAMESPACE=$(curl -sf -H "Authorization: token ${TOKEN_A}" "https://git.moguyn.cn/api/v1/user" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('login',''))" 2>/dev/null)
    if [ -z "$GITEA_NAMESPACE" ]; then
      fail "无法通过 API 获取 Gitea 用户名，请检查 OC_TOKEN_A 是否有效，或手动设置 GITEA_NAMESPACE 环境变量"
    else
      info "Gitea 命名空间：${GITEA_NAMESPACE}（当前 token 用户）"
    fi
  else
    fail "未提供 OC_TOKEN_A，无法确定 Gitea 命名空间，请设置 OC_TOKEN_A 或 GITEA_NAMESPACE 环境变量"
  fi
  # 技能列表（格式：目录名|仓库名|功能描述|关键词|安装路径）
  SKILLS=(
    "agent-browser|agent-browser|浏览器自动化|browser|global"
    "config-guardian|config-guardian|配置文件保护|config-guardian|workspace"
    "feishu-send-file|feishu-send-file|发送文件到飞书|feishu-send|global"
    "find-skills|find-skills|技能搜索安装|find-skill|global"
    "lobehub-skills-search-engine|lobehub-skills-search-engine|技能搜索引擎|lobehub|global"
    "mcporter|mcporter|MCP服务器管理|mcporter|global"
    "openclaw-cli|openclaw-cli|CLI命令参考|openclaw-cli|workspace"
    "runesleo-systematic-debugging|runesleo-systematic-debugging|系统化调试|systematic-debug|workspace"
    "safe-install|safe-install|安全安装工作流|safe-install|workspace"
    "skill-vetter|skill-vetter|技能安全审查|skill-vetter|workspace"
    "skillhub-preference|skillhub-preference|技能市场偏好|skillhub|global"
    "tavily-search-pro|tavily-search-pro|Tavily高级搜索|tavily|global"
    "feishu-approval|feishu-approval|飞书审批发起|feishu-approval|global"
  )

  for skill_line in "${SKILLS[@]}"; do
    IFS='|' read -r dir_name repo desc keyword location <<< "$skill_line"
    
    if [ "$location" = "workspace" ]; then
      base_dir="$HOME/.openclaw/workspace/skills"
    else
      base_dir="$HOME/.openclaw/skills"
    fi
    
    dest="$base_dir/$dir_name"
    
    # 精确匹配
    if [ -d "$dest" ]; then
      ((SKIPPED++))
      continue
    fi
    
    # 模糊匹配（SSH/pipe 模式下 /dev/tty 不可用时，默认跳过）
    matched=$(find "$base_dir" -maxdepth 1 -type d -iname "*${keyword}*" 2>/dev/null | head -1)
    if [ -n "$matched" ]; then
      # 非交互模式判断：SSH pipe 或脚本 stdin 重定向时无 TTY
      if [ -t 1 ] && [ -n "${TERM:-}" ] && [ -z "${OC_TOKEN_A:-}" ] || [ -t 0 ]; then
        # 可以交互：弹出询问
        prompt "检测到功能可能重复的技能："
        echo "    准备安装：${dir_name}（${desc}）"
        echo "    已有技能：${matched}"
        echo
        prompt "是否跳过安装？[y=跳过 / n=继续] (默认: y): "
        read -r answer < /dev/tty 2>/dev/null || answer="y"
        answer=${answer:-y}
      else
        warn "检测到功能重复：${dir_name} 与 $(basename "$matched")（非交互模式，默认跳过）"
        answer="y"
      fi
      if [[ "$answer" =~ ^[Yy]$ ]]; then
        ((SKIPPED++)) || true
        continue
      fi
    fi
    
    # 克隆技能（克隆后移除 .git 子目录，避免被识别为 submodule 导致 git add 失败）
    mkdir -p "$base_dir"
    if git clone --depth=1 "https://${TOKEN_A}@git.moguyn.cn/${GITEA_NAMESPACE}/${repo}.git" "$dest" &>/dev/null; then
      rm -rf "${dest}/.git"
      log "安装成功：${dir_name}"
      ((SUCCESS++)) || true
    else
      warn "安装失败：${dir_name}"
      ((FAILED++)) || true
    fi
  done
fi

# ============================================================
# 阶段 2：部署 Cron 脚本 + 注册定时任务
# ============================================================
info "阶段 2：部署 Cron 脚本..."

SCRIPTS_DIR="$HOME/.openclaw/workspace/scripts"
mkdir -p "$SCRIPTS_DIR"

# 安全巡检脚本（完整版）
AUDIT_SCRIPT="$SCRIPTS_DIR/nightly-security-audit.sh"
if [ ! -f "$AUDIT_SCRIPT" ]; then
  cp "$SELF_DIR/nightly-security-audit.sh" "$AUDIT_SCRIPT"
  chmod +x "$AUDIT_SCRIPT"
  log "创建：nightly-security-audit.sh"
else
  info "nightly-security-audit.sh 已存在，跳过"
fi

# 系统升级脚本（完整版）
UPGRADE_SCRIPT="$SCRIPTS_DIR/nightly-os-upgrade.sh"
if [ ! -f "$UPGRADE_SCRIPT" ]; then
  cp "$SELF_DIR/nightly-os-upgrade.sh" "$UPGRADE_SCRIPT"
  chmod +x "$UPGRADE_SCRIPT"
  log "创建：nightly-os-upgrade.sh"
else
  info "nightly-os-upgrade.sh 已存在，跳过"
fi

# ── 判断安装模式 ──────────────────────────────────────
# OC_INSTALL_MODE 由调用方传入：local | remote
INSTALL_MODE="${OC_INSTALL_MODE:-local}"

if [ "$INSTALL_MODE" = "local" ]; then
  # 本地安装：通过 openclaw cron 直接注册
  # OC_CRON_REPORT_TO：cron 任务执行后飞书私信汇报给谁（当前用户）
  local_report_to="${OC_CRON_REPORT_TO:-ou_f32ac815f5dcefd246cd52869ecec6d8}"
  if command -v openclaw &>/dev/null; then
    info "注册 Cron Jobs（本地模式）..."

    # CLI cron 参数已修复：--schedule→--cron, --command→--message, --notify-channel→--channel
    # 但 openclaw cron add 无法直接执行 shell 脚本，需要 Agent 通过 cron 工具注册
    # 这里只做提示，实际注册由安装后的 Agent 自动完成（isolated + agentTurn）
    info "Cron Jobs 将由 Agent 通过 cron 工具注册"
    info "  → nightly-security-audit（每天 03:00 Asia/Shanghai）"
    info "  → nightly-os-upgrade（每天 04:00 Asia/Shanghai）"
    log "Cron Jobs：注册提示已生成（Agent 将自动完成）"
  else
    warn "未找到 openclaw CLI，无法自动注册 Cron Jobs"
  fi
else
  # 远程安装：通过 SSH 在目标机器上注册
  if [ -z "${OC_REMOTE_HOST:-}" ] || [ -z "${OC_REMOTE_USER:-}" ]; then
    warn "远程模式缺少 OC_REMOTE_HOST 或 OC_REMOTE_USER，无法注册 Cron Jobs"
  else
    info "注册 Cron Jobs（远程模式：${OC_REMOTE_USER}@${OC_REMOTE_HOST}）..."

    CRON_SSH="ssh -o StrictHostKeyChecking=no ${OC_REMOTE_USER}@${OC_REMOTE_HOST}"

    # 从目标机器的 openclaw.json 自动获取第一个已授权用户的 open_id
    REMOTE_OC_JSON=$($CRON_SSH "cat ~/.openclaw/openclaw.json" 2>/dev/null)
    remote_report_to=$(echo "$REMOTE_OC_JSON" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    allow = d.get('channels', {}).get('feishu', {}).get('allowFrom', [])
    if allow:
        print(allow[0])
    else:
        print('')
except:
    print('')
" 2>/dev/null)

    if [ -z "$remote_report_to" ]; then
      warn "无法从目标机器获取 open_id，默认使用本机配置"
      remote_report_to="ou_f32ac815f5dcefd246cd52869ecec6d8"
    else
      info "目标环境已授权用户：${remote_report_to}"
    fi

    # 远程模式：通过 SSH 使用正确的 CLI 参数注册
    REMOTE_SCRIPTS_DIR="$HOME/.openclaw/workspace/scripts"
    REMOTE_AUDIT="$REMOTE_SCRIPTS_DIR/nightly-security-audit.sh"
    REMOTE_UPGRADE="$REMOTE_SCRIPTS_DIR/nightly-os-upgrade.sh"

    $CRON_SSH "openclaw cron add \\\
      --name 'nightly-security-audit' \\\
      --cron '0 3 * * *' \\\
      --tz 'Asia/Shanghai' \\\
      --session isolated \\\
      --message '执行安全巡检脚本: OC_CRON_REPORT_TO=${remote_report_to} bash ${REMOTE_AUDIT}' \\\
      --tools exec,read,write \\\
      --announce \\\
      --channel feishu \\\
      --to 'user:${remote_report_to}' \\\
      --wake next-heartbeat \\\
      2>&1" &
    PID1=$!

    $CRON_SSH "openclaw cron add \\\
      --name 'nightly-os-upgrade' \\\
      --cron '0 4 * * *' \\\
      --tz 'Asia/Shanghai' \\\
      --session isolated \\\
      --message '执行系统升级脚本: OC_CRON_REPORT_TO=${remote_report_to} bash ${REMOTE_UPGRADE}' \\\
      --tools exec,read,write \\\
      --announce \\\
      --channel feishu \\\
      --to 'user:${remote_report_to}' \\\
      --wake next-heartbeat \\\
      2>&1" &
    PID2=$!

    wait $PID1 $PID2 2>/dev/null
    log "Cron Jobs 远程注册完成"
  fi
fi



# ============================================================
# 阶段 3：git-crypt 加密 + openclaw.json 软链接
# ============================================================
info "阶段 3：git-crypt 加密配置..."

cd "$HOME/.openclaw/workspace"

# 确保已有 git 仓库
if [ ! -d ".git" ]; then
  git init
  git config user.name "OpenClaw Bot"
  git config user.email "openclaw-${HOSTNAME_SAFE}@${GITEA_NAMESPACE}.local"
  log "初始化 Git 仓库"
fi

# 初始化 git-crypt
if [ ! -d ".git/git-crypt" ]; then
  info "生成 GPG 密钥..."
  HOSTNAME_SAFE=$(hostname | tr '.' '-')
  cat > /tmp/gpg-batch.conf << EOF
%no-protection
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: ${HOSTNAME_SAFE}
Name-Email: openclaw-${HOSTNAME_SAFE}@${GITEA_NAMESPACE}.local
Expire-Date: 0
EOF
  gpg --batch --generate-key /tmp/gpg-batch.conf 2>&1 | tail -3
  rm -f /tmp/gpg-batch.conf
  
  GPG_KEY_ID=$(gpg --list-keys --keyid-format LONG | grep "^pub" | head -1 | awk '{print $2}' | cut -d'/' -f2)
  
  # 备份 GPG 密钥
  mkdir -p ~/gpg-backup
  gpg --export --armor "$GPG_KEY_ID" > ~/gpg-backup/openclaw-gpg-public.asc
  gpg --export-secret-keys --armor "$GPG_KEY_ID" > ~/gpg-backup/openclaw-gpg-private.asc
  chmod 600 ~/gpg-backup/openclaw-gpg-private.asc
  log "GPG 密钥已备份到 ~/gpg-backup/"
  
  # 初始化 git-crypt
  git-crypt init
  git-crypt add-gpg-user "$GPG_KEY_ID" 2>&1 | tail -2
  log "git-crypt 初始化完成"
  
  # 配置加密规则
  cat > .gitattributes << 'ATTR_EOF'
openclaw.json filter=git-crypt diff=git-crypt
*.env         filter=git-crypt diff=git-crypt
*.key         filter=git-crypt diff=git-crypt
*.pem         filter=git-crypt diff=git-crypt
ATTR_EOF
  
  git add .gitattributes
  git commit -m "Configure git-crypt encryption rules" 2>/dev/null || true
  log "加密规则已配置"
else
  info "git-crypt 已初始化，跳过"
fi

# openclaw.json 软链接
OC_CONFIG="$HOME/.openclaw/openclaw.json"
WS_CONFIG="$HOME/.openclaw/workspace/openclaw.json"

if [ -f "$OC_CONFIG" ] && [ ! -L "$OC_CONFIG" ]; then
  cp "$OC_CONFIG" "$WS_CONFIG"
  mv "$OC_CONFIG" "${OC_CONFIG}.before-git-crypt"
  ln -s "$WS_CONFIG" "$OC_CONFIG"
  git add openclaw.json 2>/dev/null || true
  git commit -m "Add encrypted openclaw.json" 2>/dev/null || true
  log "openclaw.json 软链接已创建"
elif [ -L "$OC_CONFIG" ]; then
  info "openclaw.json 软链接已存在，跳过"
fi

# ============================================================
# 阶段 4：Git 仓库初始化（自动创建 + 推送）
# ============================================================
info "阶段 4：配置 workspace 自动备份..."

# ── 收集 Gitea 信息（必填）──────────────────────────────
gather_gitea_info() {
  if [ -n "${OC_GITEA_URL:-}" ] && [ -n "${OC_GITEA_USER:-}" ] && [ -n "${OC_GITEA_TOKEN:-}" ]; then
    GITEA_URL="${OC_GITEA_URL}"; GITEA_USER="${OC_GITEA_USER}"; GITEA_TOKEN="${OC_GITEA_TOKEN}"
    info "使用环境变量提供的 Gitea 配置"
    return 0
  fi

  # 交互采集
  prompt "Gitea 服务器地址（如 https://gitea.example.com，留空则跳过）："
  read -r GITEA_URL < /dev/tty
  if [ -z "$GITEA_TOKEN" ]; then
    prompt "Gitea 用户名："
    read -r GITEA_USER < /dev/tty
    prompt "Gitea Access Token（需具有创建仓库和推送权限）："
    read -rs GITEA_TOKEN < /dev/tty
    echo
  fi

  if [ -z "$GITEA_URL" ] || [ -z "$GITEA_USER" ] || [ -z "$GITEA_TOKEN" ]; then
    warn "Gitea 信息不完整，跳过 workspace 备份配置"
    return 1
  fi
  return 0
}

gather_gitea_info || SKIP_GITEA=1

# ── 自动创建仓库（通过 Gitea API）──────────────────────
if [ -z "${SKIP_GITEA:-}" ]; then
  REPO_NAME="openclaw-workspace"
  API_BASE="${GITEA_URL%/}/api/v1"

  # 检查仓库是否已存在
  HTTP_CHECK=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${GITEA_TOKEN}" \
    "${API_BASE}/repos/${GITEA_USER}/${REPO_NAME}" 2>/dev/null)

  if [ "$HTTP_CHECK" = "404" ]; then
    info "仓库不存在，正在自动创建..."
    HTTP_CREATE=$(curl -s -o /dev/null -w "%{http_code}" \
      -X POST \
      -H "Authorization: Bearer ${GITEA_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "{\"name\":\"${REPO_NAME}\",\"private\":true,\"auto_init\":false}" \
      "${API_BASE}/user/repos" 2>/dev/null)
    if [ "$HTTP_CREATE" = "201" ]; then
      log "仓库 ${GITEA_USER}/${REPO_NAME} 创建成功"
    else
      warn "仓库创建失败（HTTP $HTTP_CREATE），将尝试直接添加 remote"
    fi
  elif [ "$HTTP_CHECK" = "200" ]; then
    log "仓库 ${GITEA_USER}/${REPO_NAME} 已存在"
  else
    warn "检查仓库失败（HTTP $HTTP_CHECK），将尝试直接添加 remote"
  fi

  # 构造 remote URL（优先 HTTPS，token 带在 URL 中）
  REMOTE_URL="${GITEA_URL%/}/${GITEA_USER}/${REPO_NAME}.git"
  REMOTE_URL_WITH_AUTH="${GITEA_URL%/}/${GITEA_USER}:${GITEA_TOKEN}@${REMOTE_URL#*/}"

  cd "$HOME/.openclaw/workspace"
  if git remote get-url origin &>/dev/null; then
    git remote set-url origin "$REMOTE_URL_WITH_AUTH"
    log "远程仓库 URL 已更新为 ${GITEA_USER}/${REPO_NAME}"
  else
    git remote add origin "$REMOTE_URL_WITH_AUTH"
    log "远程仓库已添加为 ${GITEA_USER}/${REPO_NAME}"
  fi
fi

# 部署 auto-sync.sh
SYNC_SCRIPT="$HOME/.openclaw/scripts/auto-sync.sh"
mkdir -p "$(dirname "$SYNC_SCRIPT")"

cat > "$SYNC_SCRIPT" << 'EOF'
#!/bin/bash
REPO_DIR="$1"
WEBHOOK_URL="${FEISHU_WEBHOOK_URL:-}"
[ -z "$REPO_DIR" ] && { echo "用法: $0 <仓库目录>"; exit 1; }
cd "$REPO_DIR" || exit 1

send_notify() {
  [ -n "$WEBHOOK_URL" ] && curl -s -X POST "$WEBHOOK_URL" \
    -H 'Content-Type: application/json' \
    -d "{\"msg_type\":\"text\",\"content\":{\"text\":\"$1\"}}" 2>/dev/null || true
}

BRANCH=$(git branch --show-current 2>/dev/null || echo "main")
echo "[$(date '+%Y-%m-%d %H:%M:%S')] 监听: $REPO_DIR (branch: $BRANCH)"

while true; do
  inotifywait -rq -e modify,create,delete,move --exclude '\.git' . 2>/dev/null
  sleep 2
  if ! git diff --quiet HEAD 2>/dev/null || [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    if ! git pull --rebase origin "$BRANCH" 2>&1; then
      git status 2>/dev/null | grep -q "rebase in progress" && { git rebase --abort 2>/dev/null; send_notify "⚠️ Workspace 同步冲突，需手动处理"; continue; }
    fi
    git status --porcelain 2>/dev/null | grep -qE '^(UU|AA|DD)' && { send_notify "⚠️ Workspace 冲突: $(git status --porcelain | grep -E '^(UU|AA|DD)')"; continue; }
    git add -A
    git commit -m "auto: $(date '+%Y-%m-%d %H:%M:%S')" 2>/dev/null && \
      { git push origin "$BRANCH" 2>&1 && echo "[$(date '+%H:%M:%S')] ✅ 同步完成" || send_notify "⚠️ 推送失败"; }
  fi
done
EOF
chmod +x "$SYNC_SCRIPT"
log "auto-sync.sh 已部署"

# 创建 systemd 服务
SYSTEMD_DIR="$HOME/.config/systemd/user"
mkdir -p "$SYSTEMD_DIR"

cat > "$SYSTEMD_DIR/openclaw-sync-main.service" << EOF
[Unit]
Description=OpenClaw Workspace Auto Sync
After=network.target

[Service]
Type=simple
ExecStart=$HOME/.openclaw/scripts/auto-sync.sh $HOME/.openclaw/workspace
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload 2>/dev/null
systemctl --user enable openclaw-sync-main.service 2>/dev/null
systemctl --user restart openclaw-sync-main.service 2>/dev/null
log "systemd 服务已启动"

# 首次提交推送
cd "$HOME/.openclaw/workspace"
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  git add -A
  git commit -m "Initial commit: OpenClaw workspace setup" 2>/dev/null || true
fi
if git remote get-url origin &>/dev/null; then
  BRANCH=$(git branch --show-current 2>/dev/null || echo "main")
  if git push -u origin "$BRANCH" 2>&1; then
    log "首次推送成功"
  else
    warn "首次推送失败，请检查远程仓库配置"
  fi
fi

# ============================================================
# 阶段 5：技能配置
# ============================================================
info "阶段 5：技能配置..."
echo ""

# ── 5.1 Dreaming + Memory-Wiki 插件配置 ────────────────
# 要求 OpenClaw >= 2026.4
OC_VERSION=$(openclaw --version 2>/dev/null | grep -oP '\d{4}\.\d+' | head -1)
OC_MAJOR=$(echo "$OC_VERSION" | cut -d. -f1)
OC_MINOR=$(echo "$OC_VERSION" | cut -d. -f2)

if [ -n "$OC_VERSION" ] && ([ "$OC_MAJOR" -gt 2026 ] || ([ "$OC_MAJOR" -eq 2026 ] && [ "$OC_MINOR" -ge 4 ])); then
  info "OpenClaw $OC_VERSION 支持 Dreaming + Memory-Wiki，正在配置..."
  
  # 检测当前配置中是否已有相关设置
  OC_CONFIG="$HOME/.openclaw/openclaw.json"
  if [ -f "$OC_CONFIG" ]; then
    # 如果 Agent 可用，由 Agent 通过 gateway config.patch 配置
    # 这里只输出提示，实际配置由安装后的 Agent 完成
    info "Dreaming 配置：将由 Agent 通过 gateway config.patch 完成"
    info "  → plugins.entries.memory-core.config.dreaming"
    info "  → plugins.entries.memory-wiki（含 vault.renderMode=obsidian）"
    log "Dreaming + Memory-Wiki：配置提示已生成（Agent 将自动完成）"
  else
    warn "未找到 openclaw.json，跳过插件配置"
  fi
else
  warn "OpenClaw ${OC_VERSION:-未知} 不支持 Dreaming + Memory-Wiki（需要 >= 2026.4）"
  warn "跳过插件配置，请升级 OpenClaw 后手动配置"
fi

# ── 5.2 QMD Memory Backend 配置 ────────────────────────
# 要求 OpenClaw >= 2026.4 + npm 全局安装 @tobilu/qmd
info "检查 QMD Memory Backend..."
if command -v qmd &>/dev/null; then
  QMD_VERSION=$(qmd --version 2>/dev/null || echo "unknown")
  log "QMD 已安装：${QMD_VERSION}"
else
  warn "QMD 未安装，正在通过 npm 安装..."
  if npm install -g @tobilu/qmd &>/dev/null; then
    log "QMD 安装成功"
  else
    warn "QMD 安装失败，Agent 将尝试手动配置"
  fi
fi

# 写入环境变量到 ~/.bashrc（防止 Vulkan 编译失败 + 国内镜像）
BASHRC="$HOME/.bashrc"
if [ -f "$BASHRC" ]; then
  # NODE_LLAMA_CPP_GPU=false（无 GPU 时必须）
  if ! grep -q "NODE_LLAMA_CPP_GPU" "$BASHRC" 2>/dev/null; then
    echo "" >> "$BASHRC"
    echo "# QMD: 强制 CPU 模式，跳过 Vulkan 编译" >> "$BASHRC"
    echo "export NODE_LLAMA_CPP_GPU=false" >> "$BASHRC"
    log "已写入 NODE_LLAMA_CPP_GPU=false 到 ~/.bashrc"
  else
    log "NODE_LLAMA_CPP_GPU 已在 ~/.bashrc 中"
  fi
  # HF_ENDPOINT（国内镜像，可选）
  if ! grep -q "HF_ENDPOINT" "$BASHRC" 2>/dev/null; then
    echo "# QMD: 国内 HuggingFace 镜像" >> "$BASHRC"
    echo "export HF_ENDPOINT=https://hf-mirror.com" >> "$BASHRC"
    log "已写入 HF_ENDPOINT 到 ~/.bashrc"
  else
    log "HF_ENDPOINT 已在 ~/.bashrc 中"
  fi
fi

info "QMD 配置：将由 Agent 通过 gateway config.patch 完成："
info "  → memory.backend: \"qmd\""
info "  → memory.qmd.searchMode: \"search\" (BM25，适合 CPU)"
info "  → memory.qmd.limits.timeoutMs: 30000"
info "  → memory.qmd.scope: 开放 direct + group 搜索"
info "  → 首次需要运行 qmd embed 下载模型（约 2GB）"
info ""
info "⚠️  关键注意事项："
info "  • OpenClaw 的 QMD 路径: ~/.openclaw/agents/<agentId>/qmd/（非 ~/.cache/qmd/）"
info "  • 首次 embed 会下载 3 个 GGUF 模型 + 编译 llama.cpp（5-10 分钟）"
info "  • 无 GPU 必须设 NODE_LLAMA_CPP_GPU=false"
info "  • searchMode \"query\" (混合搜索) CPU 太慢，建议用 \"search\" (BM25)"
info "  • bridge \"0 exported artifacts\" 是已知状态，不影响 QMD 搜索"
log "QMD：配置提示已生成（Agent 将自动完成 config.patch + embed）"

# ── 5.3 tavily-search-pro：配置 API Key ───────────────────
if [ -d "$HOME/.openclaw/workspace/skills/tavily-search-pro" ]; then
  if grep -q "TAVILY_API_KEY" "$HOME/.openclaw/workspace/.env" 2>/dev/null || \
     [ -n "${TAVILY_API_KEY:-}" ]; then
    log "tavily-search-pro：API Key 已配置"
  else
    echo ""
    info "tavily-search-pro 需要 Tavily API Key（可在 https://tavily.com 免费申请）"
    prompt "请输入 Tavily API Key（留空跳过）："
    if { true < /dev/tty; } 2>/dev/null; then
      read -r TAVILY_KEY < /dev/tty 2>/dev/null || TAVILY_KEY=""
    else
      TAVILY_KEY="${TAVILY_API_KEY:-}"
    fi
    if [ -n "$TAVILY_KEY" ]; then
      echo "TAVILY_API_KEY=${TAVILY_KEY}" >> "$HOME/.openclaw/workspace/.env"
      grep -q "TAVILY_API_KEY" "$HOME/.bashrc" 2>/dev/null || \
        echo "export TAVILY_API_KEY=${TAVILY_KEY}" >> "$HOME/.bashrc"
      log "tavily-search-pro：API Key 已保存到 .env 和 ~/.bashrc"
    else
      warn "tavily-search-pro：跳过，如需使用请手动设置 TAVILY_API_KEY 环境变量"
    fi
  fi
fi

# ── 5.4 企业微信 CLI（wecom-cli）安装与配置 ─────────────
info "检查企业微信 CLI（wecom-cli）..."

WECOM_CLI_CONFIG_DIR="${HOME}/.config/wecom"

# 安装 CLI 工具
if command -v wecom-cli &>/dev/null; then
  WECOM_CLI_VER=$(wecom-cli --version 2>/dev/null || echo "unknown")
  log "wecom-cli 已安装：${WECOM_CLI_VER}"
else
  info "安装 wecom-cli CLI 工具..."
  if npm install -g @wecom/cli &>/dev/null; then
    log "wecom-cli CLI 安装成功"
  else
    warn "wecom-cli CLI 安装失败，请手动执行: npm install -g @wecom/cli"
  fi
fi

# 安装官方 Skills（6 个：contact/doc/meeting/msg/schedule/todo）
WECOM_SKILLS_DIR="${HOME}/.agents/skills"
if [ -d "${WECOM_SKILLS_DIR}/wecomcli-contact" ]; then
  log "wecom-cli Skills 已安装（6 个）"
else
  info "安装 wecom-cli 官方 Skills..."
  if npx skills add WeComTeam/wecom-cli -y -g &>/dev/null; then
    log "wecom-cli Skills 安装成功（wecomcli-contact/doc/meeting/msg/schedule/todo）"
  else
    warn "wecom-cli Skills 安装失败，请手动执行: npx skills add WeComTeam/wecom-cli -y -g"
  fi
fi

# 配置凭证
if [ -f "${WECOM_CLI_CONFIG_DIR}/bot.enc" ]; then
  log "wecom-cli 凭证已配置"
else
  echo ""
  info "wecom-cli 需要企业微信机器人 Bot ID 和 Secret 进行配置"
  info "获取方式：https://open.work.weixin.qq.com/help2/pc/cat?doc_id=21677"

  # 支持环境变量传入
  if [ -n "${WECOM_BOT_ID:-}" ] && [ -n "${WECOM_BOT_SECRET:-}" ]; then
    info "使用环境变量提供的 Bot ID 和 Secret"
    # 尝试用 pexpect 自动配置（需要 PTY）
    if command -v python3 &>/dev/null && python3 -c "import pexpect" 2>/dev/null; then
      info "正在自动配置凭证..."
      python3 -c "
import pexpect, sys, time
p = pexpect.spawn('wecom-cli init', timeout=60, encoding='utf-8')
p.expect('请选择企微机器人接入方式', timeout=10)
time.sleep(0.5)
p.send('\x1b[B')  # 下箭头选手动模式
time.sleep(0.3)
p.send('\r')
time.sleep(1)
p.expect('Bot ID', timeout=10)
time.sleep(0.3)
p.sendline('${WECOM_BOT_ID}')
time.sleep(0.5)
p.expect('Secret', timeout=10)
time.sleep(0.3)
p.sendline('${WECOM_BOT_SECRET}')
time.sleep(3)
p.expect(pexpect.EOF, timeout=30)
" 2>/dev/null
      if [ -f "${WECOM_CLI_CONFIG_DIR}/bot.enc" ]; then
        log "wecom-cli 凭证配置成功（自动模式）"
      else
        warn "wecom-cli 自动配置失败，请手动执行: wecom-cli init"
      fi
    else
      warn "缺少 pexpect，无法自动配置，请手动执行: wecom-cli init"
    fi
  else
    # 手动配置提示
    echo ""
    info "请在终端中手动执行以下命令配置凭证："
    info "  wecom-cli init"
    info "  → 选择「手动输入 Bot ID 和 Secret」"
    info "  → 输入 Bot ID 和 Secret"
    echo ""
    info "或在 Agent 调用时提供 WECOM_BOT_ID / WECOM_BOT_SECRET 环境变量"
    echo ""
    info "配置凭证后，需在企业微信中授权各品类权限："
    info "  📄 文档:   type=1"
    info "  📅 日程:   type=2"
    info "  🎥 会议:   type=3"
    info "  💬 消息+通讯录: type=4（共享权限入口）"
    info "  ✅ 待办:   type=5"
    info "  授权入口: https://work.weixin.qq.com/ai/aiHelper/authorizationPage?str_aibotid=<BOT_ID>&type=<TYPE>&from=chat&forceInnerBrowser=1"
  fi
fi

# ── 5.5 mcporter：提示配置 MCP 服务器 ─────────────────────
if [ -d "$HOME/.openclaw/workspace/skills/mcporter" ]; then
  MCP_CFG="$HOME/.openclaw/config/mcp-servers.json"
  if [ -f "$MCP_CFG" ]; then
    log "mcporter：MCP 配置文件已存在"
  else
    warn "mcporter：尚未配置 MCP 服务器，如需使用请创建：${MCP_CFG}"
    echo "        参考命令：mcporter config add <server-name> <url>"
  fi
fi

# ── 5.6 需要飞书 OAuth 的技能：打印手动配置提示 ────────────
FEISHU_SKILLS=()
[ -d "$HOME/.openclaw/workspace/skills/feishu-send-file" ] && FEISHU_SKILLS+=("feishu-send-file")
[ -d "$HOME/.openclaw/skills/feishu-approval" ] && FEISHU_SKILLS+=("feishu-approval")

if [ ${#FEISHU_SKILLS[@]} -gt 0 ]; then
  echo ""
  warn "以下技能需要飞书 OAuth 授权，请在 OpenClaw 中手动完成："
  for s in "${FEISHU_SKILLS[@]}"; do
    echo "    • $s"
  done
  echo "    授权方式：在飞书对话框中发送 /oauth 或按提示完成授权流程"
fi

echo ""

# ============================================================
# 阶段 6：重启 Gateway 使技能生效
# ============================================================
info "阶段 6：重启 Gateway 使技能生效..."

if command -v openclaw &>/dev/null; then
  openclaw gateway restart 2>&1
  log "Gateway 已重启，所有技能已生效"
else
  warn "未找到 openclaw CLI，请手动重启 Gateway：openclaw gateway restart"
fi

# ============================================================
# 阶段 7：清除各技能的 .git 目录，变为纯文件快照
# ============================================================
info "阶段 7：清除各技能 .git 目录，还原为纯文件..."

GIT_CLEAN_COUNT=0
SKILLS_BASE="$HOME/.openclaw/skills"
WS_SKILLS_BASE="$HOME/.openclaw/workspace/skills"

# 清理 global skills（~/.openclaw/skills/）
for skill_git in "$SKILLS_BASE"/*/.git "$WS_SKILLS_BASE"/*/.git; do
  [ -d "$skill_git" ] || continue
  skill_dir="${skill_git%/.git}"
  skill_name=$(basename "$skill_dir")
  
  # 跳过 bootstrap-skills 自身（它需要保留 .git 以便后续更新）
  [ "$skill_name" = "bootstrap-skills" ] && continue
  
  rm -rf "$skill_git"
  GIT_CLEAN_COUNT=$((GIT_CLEAN_COUNT + 1))
  log "已清除：${skill_name}"
done

if [ "$GIT_CLEAN_COUNT" -gt 0 ]; then
  log "共清除 $GIT_CLEAN_COUNT 个技能的 .git 目录"
else
  info "未发现需要清理的 .git 目录"
fi

# ============================================================
# 完成输出
# ============================================================
echo
echo "=================================================="
echo "  ✅ OpenClaw 环境初始化完成！"
echo "=================================================="
echo "安装统计：成功 $SUCCESS，跳过 $SKIPPED，失败 $FAILED"
echo ""
echo "已完成配置："
echo "  ✅ git-crypt 加密 + openclaw.json 软链接"
if [ -z "${SKIP_GITEA:-}" ]; then
  echo "  ✅ workspace 备份 → ${GITEA_USER}/${REPO_NAME:-openclaw-workspace}"
  echo "  ✅ inotify 实时同步服务（systemd 管理）"
else
  echo "  ⚠  workspace 备份跳过（未提供 Gitea 配置）"
fi
echo "  ✅ Dreaming + Memory-Wiki 插件配置（需 >= 2026.4）"
echo "  ✅ QMD Memory Backend 环境变量已写入 ~/.bashrc"
echo "  ✅ 各技能 .git 目录已清除（变为纯文件快照）"
echo "  ✅ Gateway 已重启"
echo ""
if [ "$INSTALL_MODE" = "remote" ]; then
  echo ""
  info "远程安装：Cron Jobs 已在目标机器自动注册，飞书私信已汇报"
fi
echo "待 Agent 完成后："
echo "  ⚠  Agent 将检查各技能配置状态并显示结果"
echo "  ⚠  Agent 将配置 Tavily API Key（如已提供）"
echo "  ⚠  其他待手动完成："
if [ "$INSTALL_MODE" = "local" ]; then
  echo "     - Cron Jobs 已自动注册（如需修改：openclaw cron list）"
fi
echo "     - 完成飞书 OAuth 授权（feishu-send-file / feishu-approval）"
echo "     - mcporter MCP 服务器（如需）"
echo "     - QMD config.patch（memory.backend + searchMode + timeout + scope）"
echo "     - QMD 首次 embed（qmd embed，下载约 2GB 模型）"
if [ -f "$HOME/gpg-backup/openclaw-gpg-private.asc" ]; then
  echo "     - 备份 GPG 私钥到安全位置：~/gpg-backup/openclaw-gpg-private.asc"
fi
echo "=================================================="
