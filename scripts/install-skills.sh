#!/bin/bash
# =============================================================================
# install-skills.sh — 传米科技 OpenClaw 基础技能一键安装脚本
# 来源：https://github.com/transiglobal
# 用法：
#   本地安装：bash install-skills.sh
#   远程安装：ssh user@host 'bash -s' < install-skills.sh
# =============================================================================

set -e

# 颜色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
fail() { echo -e "${RED}[✗]${NC} $1"; }

# 安装目录
WORKSPACE_SKILLS="${HOME}/.openclaw/workspace/skills"
GLOBAL_SKILLS="${HOME}/.openclaw/skills"
ORG="https://github.com/transiglobal"

# 确保目录存在
mkdir -p "$WORKSPACE_SKILLS"
mkdir -p "$GLOBAL_SKILLS"

echo ""
echo "=================================================="
echo "  传米科技 OpenClaw 基础技能安装器"
echo "  来源: github.com/transiglobal"
echo "=================================================="
echo ""

# =============================================================================
# workspace skills（安装到 ~/.openclaw/workspace/skills/）
# =============================================================================
WORKSPACE_REPOS=(
  "agent-browser:agent-browser"
  "config-guardian:config-guardian"
  "elatia-humanizer-zh:elatia-humanizer-zh"
  "feishu-send-file:feishu-send-file"
  "find-skills:find-skills"
  "lobehub-skills-search-engine:lobehub-skills-search-engine"
  "mcporter:mcporter"
  "narrative-voice:narrative-voice"
  "openclaw-cli:openclaw-cli"
  "smart-agent-memory:openclaw-skills-smart-agent-memory"
  "runesleo-systematic-debugging:runesleo-systematic-debugging"
  "safe-install:safe-install"
  "self-improving-agent:self-improving-agent"
  "skill-vetter:skill-vetter"
  "skillhub-preference:skillhub-preference"
  "tavily-search-pro:tavily-search-pro"
  "proactive-agent:proactive-agent"
)

# global skills（安装到 ~/.openclaw/skills/）
GLOBAL_REPOS=(
  "feishu-approval:feishu-approval"
)

install_skill() {
  local repo="$1"
  local dir_name="$2"
  local target_dir="$3"
  local dest="$target_dir/$dir_name"

  if [ -d "$dest" ]; then
    warn "已存在，跳过: $dir_name"
    return 0
  fi

  if git clone --depth=1 "$ORG/$repo.git" "$dest" 2>/dev/null; then
    log "安装成功: $dir_name"
  else
    fail "安装失败: $repo"
    return 1
  fi
}

echo ">>> 安装 workspace skills..."
SUCCESS=0
FAIL=0
for item in "${WORKSPACE_REPOS[@]}"; do
  repo="${item%%:*}"
  dir="${item##*:}"
  if install_skill "$repo" "$dir" "$WORKSPACE_SKILLS"; then
    ((SUCCESS++)) || true
  else
    ((FAIL++)) || true
  fi
done

echo ""
echo ">>> 安装 global skills..."
for item in "${GLOBAL_REPOS[@]}"; do
  repo="${item%%:*}"
  dir="${item##*:}"
  if install_skill "$repo" "$dir" "$GLOBAL_SKILLS"; then
    ((SUCCESS++)) || true
  else
    ((FAIL++)) || true
  fi
done

echo ""
echo "=================================================="
echo "  安装完成：成功 ${SUCCESS} 个，失败 ${FAIL} 个"
echo "=================================================="
echo ""

if [ "$FAIL" -gt 0 ]; then
  warn "部分技能安装失败，请检查网络或 GitHub 访问权限"
  exit 1
fi

log "所有基础技能安装完成！重启 OpenClaw 会话后生效。"
