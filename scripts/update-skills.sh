#!/bin/bash
set -uo pipefail

# ══════════════════════════════════════════════════════════════
#  OpenClaw 技能更新脚本 v2.0
#  从第三方原始来源拉取最新版 → 与本地 diff → 合并更新 → 推送私有库
# ══════════════════════════════════════════════════════════════

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
log()    { echo -e "${GREEN}[✓]${NC} $1"; }
warn()   { echo -e "${YELLOW}[!]${NC} $1"; }
fail()   { echo -e "${RED}[✗]${NC} $1"; exit 1; }
info()   { echo -e "${BLUE}[i]${NC} $1"; }
prompt() { echo -e "${YELLOW}[?]${NC} $1"; }
header() { echo -e "\n${CYAN}══════ $1 ══════${NC}"; }

# ── 参数解析 ────────────────────────────────────────────
MODE="interactive"
TARGET_SKILL=""
TOKEN_A="${OC_TOKEN_A:-}"
DRY_RUN=false
NO_PUSH=false

# 动态获取 Gitea 命名空间（优先环境变量，否则通过 API 获取当前 token 用户名）
GITEA_NAMESPACE="${GITEA_NAMESPACE:-}"
if [ -z "$GITEA_NAMESPACE" ] && [ -n "$TOKEN_A" ]; then
  GITEA_NAMESPACE=$(curl -sf -H "Authorization: token ${TOKEN_A}" "https://git.moguyn.cn/api/v1/user" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('login',''))" 2>/dev/null)
  [ -z "$GITEA_NAMESPACE" ] && GITEA_NAMESPACE="transiglobal"
fi

usage() {
  echo "用法："
  echo "  $0                          # 交互模式"
  echo "  $0 -s <skill-name>          # 更新单个技能"
  echo "  $0 --all                    # 更新所有有第三方来源的技能"
  echo "  $0 --all --dry-run          # 预览变更（不实际更新）"
  echo "  $0 --all --no-push          # 更新但不推送到私有库"
  echo ""
  echo "环境变量："
  echo "  OC_TOKEN_A    私有库 Token（推送时需要）"
  echo "  GITEA_NAMESPACE  Gitea 命名空间（默认：当前 token 用户名）"
  echo "  https_proxy   代理（访问 GitHub 时可能需要）"
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--skill)   TARGET_SKILL="$2"; MODE="single"; shift 2 ;;
    --all)        MODE="all"; shift ;;
    --dry-run)    DRY_RUN=true; shift ;;
    --no-push)    NO_PUSH=true; shift ;;
    -h|--help)    usage ;;
    *)            warn "未知参数：$1"; usage ;;
  esac
done

# ── 备份目录 ────────────────────────────────────────────
BACKUP_ROOT="$HOME/.openclaw/workspace/.skill-backups"
mkdir -p "$BACKUP_ROOT"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# ══════════════════════════════════════════════════════════════
#  技能注册表：本地名称|描述|安装位置|第三方原始来源|私有仓名称
#  第三方来源为空 = 传米自研，无上游更新
# ══════════════════════════════════════════════════════════════
SKILLS=(
  # Git 来源（GitHub）
  "agent-browser|浏览器自动化|global|https://github.com/TheSethRose/Agent-Browser-CLI.git|agent-browser"
  "agent-reach|全网搜索工具|global|https://github.com/Panniantong/Agent-Reach.git|agent-reach|agent-reach/skill"
  "safe-install|安全安装工作流|workspace|https://github.com/mike007jd/openclaw-skills.git|safe-install|safe-install"
  # ClawHub 来源（slug 不带 owner/）
  "ssh-essentials|SSH命令速查|global|clawhub:ssh-essentials|ssh-essentials"
  "tavily-search-pro|Tavily高级搜索|global|clawhub:tavily-search-pro|tavily-search-pro"
  "skill-vetter|技能安全审查|workspace|clawhub:skill-vetter|skill-vetter"
  "mcporter|MCP服务器管理|global|clawhub:mcporter|mcporter"
  "config-guardian|配置文件保护|workspace|clawhub:config-guardian|config-guardian"
  "openclaw-cli|CLI命令参考|workspace|clawhub:openclaw-cli|openclaw-cli"
  "runesleo-systematic-debugging|系统化调试|workspace|clawhub:runesleo-systematic-debugging|runesleo-systematic-debugging"
  # Web 来源（lobehub/skillhub）
  "lobehub-skills-search-engine|技能搜索引擎|global|https://lobehub.com/skills/skill.md|lobehub-skills-search-engine"
  "skillhub-preference|技能市场偏好|global|https://skillhub.cn/install/skillhub.md|skillhub-preference"

  # 传米自研 / 自定义技能（无第三方来源，不参与更新流程）
  "find-skills|技能搜索安装|global||find-skills"
  "feishu-send-file|发送文件到飞书|global||feishu-send-file"
  "feishu-approval|飞书审批发起|global||feishu-approval"
)

# ══════════════════════════════════════════════════════════════
#  辅助函数
# ══════════════════════════════════════════════════════════════

# 查找技能本地安装路径
find_skill_dir() {
  local dir_name="$1"
  local location="$2"
  local primary fallback
  if [ "$location" = "workspace" ]; then
    primary="$HOME/.openclaw/workspace/skills"
    fallback="$HOME/.openclaw/skills"
  else
    primary="$HOME/.openclaw/skills"
    fallback="$HOME/.openclaw/workspace/skills"
  fi
  if [ -d "$primary/$dir_name" ]; then
    echo "$primary/$dir_name"
  elif [ -d "$fallback/$dir_name" ]; then
    echo "$fallback/$dir_name"
  fi
}

# 从网页来源下载 SKILL.md（lobehub/skillhub 等）
clone_from_web() {
  local url="$1"
  local dest="$2"
  # 尝试用 curl 下载
  if curl -sL --max-time 15 "$url" -o "$dest/SKILL.md" 2>/dev/null; then
    if [ -s "$dest/SKILL.md" ]; then
      return 0
    fi
  fi
  return 1
}
clone_from_clawhub() {
  local slug="$1"
  local dest="$2"
  if ! command -v clawhub &>/dev/null; then
    warn "未安装 clawhub CLI，跳过 clawhub 来源：$slug"
    return 1
  fi
  # clawhub install 安装到 --workdir/skills/<slug>
  local workdir=$(mktemp -d)
  if clawhub --workdir "$workdir" --no-input install "$slug" 2>/dev/null; then
    # 安装成功，把内容移到 dest
    local installed="$workdir/skills/$slug"
    if [ -d "$installed" ]; then
      cp -a "$installed/." "$dest/"
      rm -rf "$workdir"
      return 0
    fi
  fi
  rm -rf "$workdir"
  return 1
}

# 从 git 来源克隆（支持 subdir 参数）
clone_from_git() {
  local url="$1"
  local dest="$2"
  local subdir="${3:-}"
  local proxy_args=""
  local tmp_clone=$(mktemp -d)
  # 如果需要代理
  if [ -n "${https_proxy:-}" ]; then
    git clone --depth=1 -c "http.proxy=$https_proxy" -c "https.proxy=$https_proxy" "$url" "$tmp_clone" &>/dev/null
  else
    git clone --depth=1 "$url" "$tmp_clone" &>/dev/null
  fi
  local rc=$?
  if [ $rc -ne 0 ]; then
    rm -rf "$tmp_clone"
    return 1
  fi
  # 如果有 subdir，只复制子目录内容
  if [ -n "$subdir" ] && [ -d "$tmp_clone/$subdir" ]; then
    cp -a "$tmp_clone/$subdir/." "$dest/"
  else
    cp -a "$tmp_clone/." "$dest/"
  fi
  rm -rf "$tmp_clone"
  return 0
}

# 解析 diff -rq 输出，提取相对路径
parse_diff_files() {
  local raw="$1"
  local strip_prefix="$2"
  [ -z "$raw" ] && return
  echo "$raw" | while IFS= read -r line; do
    local rel=""
    case "$line" in
      Files\ *)
        full_path=$(echo "$line" | sed 's/^Files //;s/ and .*//')
        rel="${full_path#$strip_prefix/}"
        ;;
      Only\ in\ *)
        dir_part=$(echo "$line" | sed "s|^Only in ${strip_prefix}/\(.*\): .*|\1|;s|^Only in ${strip_prefix}: ||")
        file_part=$(echo "$line" | sed 's|^Only in [^:]*: ||')
        if [ "$dir_part" != "$line" ] && [ -n "$dir_part" ]; then
          rel="${dir_part}/${file_part}"
        else
          rel="$file_part"
        fi
        ;;
      File\ *)
        full_path=$(echo "$line" | sed 's/^File //;s/ is .*//')
        rel="${full_path#$strip_prefix/}"
        ;;
    esac
    if [ -n "$rel" ] && [ "${rel:0:1}" != "/" ]; then
      echo "$rel"
    fi
  done | sort -u
}

# ══════════════════════════════════════════════════════════════
#  推送到私有库（独立函数，供自研和第三方技能共用）
# ══════════════════════════════════════════════════════════════
push_to_private() {
  local src_dir="$1"  # 本地技能目录
  local dir_name="$2"
  local private_repo="$3"

  if [ "$NO_PUSH" = true ]; then
    info "跳过推送（--no-push）"
    return 0
  fi
  if [ -z "$TOKEN_A" ]; then
    warn "未提供 OC_TOKEN_A，跳过推送"
    return 1
  fi

  info "推送到私有库 git.moguyn.cn/${GITEA_NAMESPACE}/${private_repo}..."
  local push_tmp=$(mktemp -d)
  if git clone --depth=1 "https://${TOKEN_A}@git.moguyn.cn/${GITEA_NAMESPACE}/${private_repo}.git" "$push_tmp" 2>/dev/null; then
    rsync -a --delete --exclude='.git' "$src_dir/" "$push_tmp/"
    cd "$push_tmp"
    git add -A
    git config user.name "OpenClaw Bot" 2>/dev/null
    git config user.email "openclaw-bot@${GITEA_NAMESPACE}.local" 2>/dev/null
    if git diff --cached --quiet 2>/dev/null; then
      info "私有库已是最新，无需推送"
      cd - &>/dev/null
      rm -rf "$push_tmp"
      return 0
    else
      git commit -m "sync: update $dir_name $(date '+%Y-%m-%d')" 2>/dev/null
      if git push origin HEAD 2>&1; then
        log "已推送到私有库"
        cd - &>/dev/null
        rm -rf "$push_tmp"
        return 0
      else
        warn "推送到私有库失败（见上方错误信息）"
        cd - &>/dev/null
        rm -rf "$push_tmp"
        return 1
      fi
    fi
  else
    warn "克隆私有库失败，跳过推送（仓库可能不存在，需先在 moguyn 创建）"
    rm -rf "$push_tmp"
    return 1
  fi
}

# ══════════════════════════════════════════════════════════════
#  核心函数：更新单个技能
# ══════════════════════════════════════════════════════════════
update_skill() {
  local dir_name="$1"
  local desc="$2"
  local location="$3"
  local source_url="$4"
  local private_repo="$5"
  local subdir="${6:-}"

  header "$dir_name ($desc)"

  # ── Step 0: 检查第三方来源 ──
  if [ -z "$source_url" ]; then
    info "传米自研技能，无第三方上游来源"
    # 自研技能：只推送到私有库做备份
    local self_dest
    self_dest=$(find_skill_dir "$dir_name" "$location")
    if [ -z "$self_dest" ]; then
      warn "本地不存在 $dir_name，跳过"
      return 2
    fi
    push_to_private "$self_dest" "$dir_name" "$private_repo"
    return $?
  fi

  # ── Step 1: 查找本地安装路径 ──
  local dest
  dest=$(find_skill_dir "$dir_name" "$location")
  if [ -z "$dest" ]; then
    warn "本地不存在 $dir_name，跳过（如需安装请用 install-skills.sh）"
    return 1
  fi
  info "本地路径：$dest"

  # ── Step 2: 从第三方原始来源克隆最新版到临时目录 ──
  local tmp_dir=$(mktemp -d)
  info "从第三方来源拉取最新版..."
  info "  来源：$source_url"

  if [[ "$source_url" == clawhub:* ]]; then
    # ClawHub 来源
    local slug="${source_url#clawhub:}"
    if ! clone_from_clawhub "$slug" "$tmp_dir"; then
      warn "ClawHub 克隆失败：$slug，跳过"
      rm -rf "$tmp_dir"
      return 1
    fi
  elif [[ "$source_url" == https://lobehub.com/* ]] || [[ "$source_url" == https://skillhub.cn/* ]]; then
    # Web 来源（lobehub/skillhub）
    if ! clone_from_web "$source_url" "$tmp_dir"; then
      warn "网页下载失败：$source_url，跳过"
      rm -rf "$tmp_dir"
      return 1
    fi
  else
    # Git 来源（GitHub 等）
    if ! clone_from_git "$source_url" "$tmp_dir" "$subdir"; then
      warn "克隆失败：$source_url"
      info "  尝试使用代理..."
      if [ -n "${https_proxy:-}" ]; then
        warn "代理已配置但仍失败，跳过"
      else
        warn "未配置代理，如需访问 GitHub 请设置 https_proxy"
      fi
      rm -rf "$tmp_dir"
      return 1
    fi
  fi

  # ── Step 3: diff 对比（本地 vs 第三方最新版）──
  local diff_output reverse_diff
  diff_output=$(LC_ALL=C diff -rq --exclude='.git' "$dest" "$tmp_dir" 2>/dev/null | head -50)
  reverse_diff=$(LC_ALL=C diff -rq --exclude='.git' "$tmp_dir" "$dest" 2>/dev/null | head -50)

  if [ -z "$diff_output" ] && [ -z "$reverse_diff" ]; then
    log "$dir_name：本地已是最新，无需更新"
    rm -rf "$tmp_dir"
    return 0
  fi

  # 解析差异文件
  local local_diff_files upstream_diff_files
  local_diff_files=$(parse_diff_files "$diff_output" "$dest")
  upstream_diff_files=$(parse_diff_files "$reverse_diff" "$tmp_dir")

  local local_only_mods=()
  local upstream_only_mods=()
  local conflicting_mods=()

  for f in $local_diff_files; do
    if echo "$upstream_diff_files" | grep -qxF "$f"; then
      conflicting_mods+=("$f")
    else
      local_only_mods+=("$f")
    fi
  done
  for f in $upstream_diff_files; do
    local in_conflict=false
    for c in "${conflicting_mods[@]:-}"; do [ "$c" = "$f" ] && in_conflict=true; done
    [ "$in_conflict" = "false" ] && upstream_only_mods+=("$f")
  done

  echo "    本地修改：${#local_only_mods[@]} 个文件"
  echo "    上游变更：${#upstream_only_mods[@]} 个文件"
  echo "    冲突文件：${#conflicting_mods[@]} 个文件"

  # Dry run 到此结束
  if [ "$DRY_RUN" = true ]; then
    info "🔍 [DRY RUN] 以上为预览结果，未实际修改"
    rm -rf "$tmp_dir"
    return 0
  fi

  # ── Step 4: 备份本地修改 ──
  local backup_dir="$BACKUP_ROOT/${dir_name}_${TIMESTAMP}"
  if [ ${#local_only_mods[@]} -gt 0 ] || [ ${#conflicting_mods[@]} -gt 0 ]; then
    mkdir -p "$backup_dir"
    for f in "${local_only_mods[@]:-}" "${conflicting_mods[@]:-}"; do
      [ -z "$f" ] && continue
      if [ -f "$dest/$f" ]; then
        mkdir -p "$backup_dir/$(dirname "$f")"
        cp "$dest/$f" "$backup_dir/$f"
      fi
    done
    log "本地修改已备份到：$backup_dir"
  fi

  # ── Step 5: 合并更新（用上游版本覆盖）──
  info "应用上游更新..."
  rm -rf "$dest/.git" 2>/dev/null
  rsync -a --delete --exclude='.git' "$tmp_dir/" "$dest/"
  rm -rf "$tmp_dir"
  log "$dir_name：已更新到上游最新版本"

  # ── Step 6: 自动恢复纯本地修改（无冲突的文件）──
  local auto_merged=0
  if [ ${#local_only_mods[@]} -gt 0 ] && [ -d "$backup_dir" ]; then
    for f in "${local_only_mods[@]:-}"; do
      [ -z "$f" ] && continue
      local is_conflict=false
      for c in "${conflicting_mods[@]:-}"; do [ "$c" = "$f" ] && is_conflict=true; done
      if [ "$is_conflict" = "false" ] && [ -f "$backup_dir/$f" ]; then
        cp "$backup_dir/$f" "$dest/$f"
        ((auto_merged++)) || true
      fi
    done
    [ $auto_merged -gt 0 ] && log "✅ 已自动恢复 $auto_merged 个纯本地修改文件"
  fi

  # ── Step 7: 验证（基本检查）──
  if [ ! -f "$dest/SKILL.md" ]; then
    warn "⚠ 更新后 SKILL.md 丢失，请检查！"
  else
    log "验证通过：SKILL.md 存在"
  fi

  # ── Step 8: 生成报告 ──
  if [ -d "$backup_dir" ]; then
    {
      echo "# 技能更新备份：$dir_name"
      echo "# 时间：$(date '+%Y-%m-%d %H:%M:%S')"
      echo "# 第三方来源：$source_url"
      echo "# 私有库：git.moguyn.cn/${GITEA_NAMESPACE}/${private_repo}"
      echo ""
      echo "## 本地修改文件（已自动保留）"
      for f in "${local_only_mods[@]:-}"; do [ -n "$f" ] && echo "- $f"; done
      echo ""
      echo "## 冲突文件（需要手动合并）"
      for f in "${conflicting_mods[@]:-}"; do [ -n "$f" ] && echo "- $f"; done
      echo ""
      echo "## 上游变更文件"
      for f in "${upstream_only_mods[@]:-}"; do [ -n "$f" ] && echo "- $f"; done
      echo ""
      echo "## 合并命令"
      for f in "${conflicting_mods[@]:-}"; do
        [ -z "$f" ] && continue
        echo "diff '$backup_dir/$f' '$dest/$f'"
      done
    } > "$backup_dir/UPDATE_REPORT.md"
  fi

  # ── Step 9: 推送到私有库 ──
  push_to_private "$dest" "$dir_name" "$private_repo"

  # ── 结果摘要 ──
  echo ""
  if [ ${#conflicting_mods[@]} -gt 0 ]; then
    warn "⚠ ${#conflicting_mods[@]} 个文件存在冲突，需要手动合并"
    echo "    备份位置：$backup_dir/"
    echo "    请查看：UPDATE_REPORT.md"
  fi

  return 0
}

# ══════════════════════════════════════════════════════════════
#  主流程
# ══════════════════════════════════════════════════════════════

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║    OpenClaw 技能更新工具 v2.0                    ║"
echo "║    第三方来源 → 本地合并 → 推送私有库            ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

case "$MODE" in
  single)
    found=false
    for skill_line in "${SKILLS[@]}"; do
      IFS='|' read -r dir_name desc location source_url private_repo subdir <<< "$skill_line"
      if [ "$dir_name" = "$TARGET_SKILL" ]; then
        update_skill "$dir_name" "$desc" "$location" "$source_url" "$private_repo" "$subdir"
        found=true
        break
      fi
    done
    [ "$found" = "false" ] && fail "未找到技能：$TARGET_SKILL"
    ;;

  all)
    # 只处理有第三方来源的技能
    count=0
    for skill_line in "${SKILLS[@]}"; do
      IFS='|' read -r dir_name desc location source_url private_repo subdir <<< "$skill_line"
      [ -n "$source_url" ] && ((count++)) || true
    done
    info "待检查：$count 个有第三方来源的技能（自研技能已跳过）"
    [ "$DRY_RUN" = true ] && info "🔍 DRY RUN 模式：仅预览"
    echo ""

    UPDATED=0 SKIPPED=0 SELF_MADE=0 FAILED=0

    for skill_line in "${SKILLS[@]}"; do
      IFS='|' read -r dir_name desc location source_url private_repo subdir <<< "$skill_line"
      [ -z "$source_url" ] && { ((SELF_MADE++)) || true; continue; }

      dir=$(find_skill_dir "$dir_name" "$location")
      [ -z "$dir" ] && { ((SKIPPED++)) || true; continue; }

      update_skill "$dir_name" "$desc" "$location" "$source_url" "$private_repo" "$subdir"
      rc=$?
      case $rc in
        0) ((UPDATED++)) || true ;;
        2) ((SELF_MADE++)) || true ;;
        *) ((FAILED++)) || true ;;
      esac
    done

    echo ""
    header "更新完成"
    echo "  已更新：$UPDATED"
    echo "  已最新：$SKIPPED（无差异）"
    echo "  自研跳过：$SELF_MADE"
    echo "  失败：$FAILED"
    echo "  备份目录：$BACKUP_ROOT/"
    [ "$DRY_RUN" = false ] && info "建议重启 Gateway：openclaw gateway restart"
    ;;

  interactive)
    info "检测本地已安装的技能..."
    echo ""

    local available=()
    local idx=1
    echo "  编号  技能名称                  来源                    描述"
    echo "  ────  ────────────────────────  ──────────────────────  ──────"

    for skill_line in "${SKILLS[@]}"; do
      IFS='|' read -r dir_name desc location source_url private_repo subdir <<< "$skill_line"
      local dir
      dir=$(find_skill_dir "$dir_name" "$location")
      [ -z "$dir" ] && continue

      local src_display
      if [ -z "$source_url" ]; then
        src_display="自研（无上游）"
      elif [[ "$source_url" == clawhub:* ]]; then
        src_display="ClawHub"
      else
        src_display=$(echo "$source_url" | sed 's|https://||;s|.git$||;s|github.com/||')
      fi
      printf "  %2d    %-25s %-23s %s\n" "$idx" "$dir_name" "$src_display" "$desc"
      available+=("$skill_line")
      ((idx++)) || true
    done

    if [ ${#available[@]} -eq 0 ]; then
      warn "本地没有找到任何可更新的技能"
      exit 0
    fi

    echo ""
    echo "  0     全部更新（仅第三方来源）"
    echo ""
    prompt "请选择（0=全部，q=退出）："
    read -r choice < /dev/tty

    [ "$choice" = "q" ] || [ "$choice" = "Q" ] || [ -z "$choice" ] && { info "已取消"; exit 0; }

    if [ "$choice" = "0" ]; then
      UPDATED=0 FAILED=0
      for skill_line in "${available[@]}"; do
        IFS='|' read -r dir_name desc location source_url private_repo subdir <<< "$skill_line"
        [ -z "$source_url" ] && continue
        update_skill "$dir_name" "$desc" "$location" "$source_url" "$private_repo" "$subdir"
        [ $? -eq 0 ] && ((UPDATED++)) || ((FAILED++)) || true
      done
      echo ""
      header "更新完成"
      echo "  成功：$UPDATED，失败：$FAILED"
      echo "  备份：$BACKUP_ROOT/"
      info "建议重启 Gateway：openclaw gateway restart"
    else
      if [ "$choice" -ge 1 ] && [ "$choice" -le ${#available[@]} ] 2>/dev/null; then
        skill_line="${available[$((choice-1))]}"
        IFS='|' read -r dir_name desc location source_url private_repo subdir <<< "$skill_line"
        update_skill "$dir_name" "$desc" "$location" "$source_url" "$private_repo" "$subdir"
        echo ""
        info "建议重启 Gateway：openclaw gateway restart"
      else
        fail "无效选择：$choice"
      fi
    fi
    ;;
esac

echo ""
log "完成 ✅"
