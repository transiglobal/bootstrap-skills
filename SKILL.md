---
name: bootstrap-skills
description: 传米科技 OpenClaw 完整环境初始化工具 v3.1。一键完成：重复检测+安装14个基础技能、Dreaming+Memory-Wiki插件配置、Cron Jobs注册（本地自动/远程提示）、git-crypt加密openclaw.json、workspace实时备份。触发词："安装基础技能"、"初始化技能"、"bootstrap skills"、"新机器部署"。
---

# Bootstrap Skills v3.1

传米科技 OpenClaw 完整环境初始化工具。

## 执行阶段

| 阶段 | 内容 |
|------|------|
| 0 | 依赖检查与自动安装（git/git-crypt/gpg/inotifywait）|
| 1 | 重复技能检测 + 安装 14 个基础技能 |
| 1.5 | 配置 Dreaming + Memory-Wiki 插件（要求 OpenClaw >= 2026.4） |
| 2 | 部署 Cron 脚本 + 注册定时任务（本地自动/远程提示）|
| 3 | git-crypt 加密 + openclaw.json 软链接 |
| 4 | Gitea 仓库自动创建 + 推送 + inotify 实时同步 |

## 必填信息（阶段 1 & 4）

| | Token A（技能下载）| Gitea 配置（workspace 备份）|
|--|--|--|
| 来源 | 传米科技提供 | 用户自己提供 |
| 用途 | 从 git.moguyn.cn 克隆技能 | 自动创建仓库并推送备份 |
| 必填 | ✅ 是 | ✅ 是（地址 + 用户名 + Token）|

**Gitea 配置说明**：
- 服务器地址：如 `https://gitea.example.com`
- 用户名：Gitea 账户用户名（仓库将创建在该用户下，非组织）
- Access Token：需具有 `repo` 权限（创建仓库 + 推送）
- 仓库名：自动使用 `openclaw-workspace`（不存在则自动创建）

## 安装的技能（14 个）+ 插件配置

### global skills（9 个）
agent-browser、feishu-send-file、find-skills、lobehub-skills-search-engine、mcporter、skillhub-preference、tavily-search-pro、proactive-agent、feishu-approval

### workspace skills（5 个）
config-guardian、openclaw-cli、runesleo-systematic-debugging、safe-install、skill-vetter

### 插件配置（阶段 1.5）

**要求**：OpenClaw >= 2026.4

| 插件 | 配置内容 |
|------|---------|
| memory-core (Dreaming) | 三阶段记忆整理（Light→REM→Deep），每天 04:30 自动运行 |
| memory-wiki | Bridge 模式联动 memory-core，vault 存储在 ~/.openclaw/wiki/main，renderMode=obsidian |

> `openclaw-skills-smart-agent-memory` 和 `self-improving-agent` 已被移除，功能由 Dreaming + Memory-Wiki 替代。

## 用法

### 本地安装
```bash
bash ~/.openclaw/workspace/skills/bootstrap-skills/scripts/install-skills.sh
```

### SSH 远程安装
```bash
# 由 Agent 设置 OC_REMOTE_HOST / OC_REMOTE_USER 后调用：
OC_INSTALL_MODE=remote \
OC_REMOTE_HOST=43.134.173.17 \
OC_REMOTE_USER=root \
bash ~/.openclaw/workspace/skills/bootstrap-skills/scripts/install-skills.sh
```

### 环境变量（全部可选）

| 变量 | 用途 |
|------|------|
| `OC_TOKEN_A` | 技能下载 Token（直接使用，不保存）|
| `OC_GITEA_URL` | Gitea 服务器地址 |
| `OC_GITEA_USER` | Gitea 用户名 |
| `OC_GITEA_TOKEN` | Gitea Access Token |
| `OC_INSTALL_MODE` | `local` / `remote`（由 Agent 调用前设置）|
| `OC_REMOTE_HOST` | 远程目标机器 IP/域名（仅 remote 模式）|
| `OC_REMOTE_USER` | 远程 SSH 用户名（仅 remote 模式，通常为 root）|
| `TAVILY_API_KEY` | Tavily API Key |

## Agent 调用指南

### 安装技能

用户说"安装基础技能"、"初始化技能"、"新机器部署"时：
1. 询问是本地安装还是远程安装
2. 提醒准备好：
   - **Token A**（传米科技提供）：技能下载
   - **Gitea Access Token**：具有创建仓库和推送权限（用户自己的 Gitea 服务器）
   - **Tavily API Key**（可选）：https://tavily.com 免费申请
3. 根据回答设置环境变量后执行脚本：
   - 本地：`OC_INSTALL_MODE=local bash install-skills.sh`
   - 远程：`OC_INSTALL_MODE=remote OC_REMOTE_HOST=<目标IP> OC_REMOTE_USER=<用户> bash install-skills.sh`
     - 脚本自动从目标机器的 `~/.openclaw/openclaw.json` 获取 `channels.feishu.allowFrom[0]` 作为飞书通知目标用户
     - 注册完成后由目标机器的 Agent 通过 cron 工具完成
4. 脚本末尾自动重启 Gateway
5. 脚本执行完毕后，由 Agent 自动完成：
   - 检查各技能配置状态并展示
   - 如提供了 Tavily API Key，写入配置
6. 将"待完成后"部分展示给用户

### 更新技能（保留本地修改）

用户说"更新技能"、"升级技能"、"技能有新版"时：
1. 确认要更新哪个技能（或全部）
2. 需要 **Token A**（传米科技提供）
3. 执行 `update-skills.sh`：
   - 交互模式（推荐）：`bash update-skills.sh`
   - 更新单个：`OC_TOKEN_A=<token> bash update-skills.sh -s <skill-name>`
   - 全部更新：`OC_TOKEN_A=<token> bash update-skills.sh --all`
   - 预览变更：`OC_TOKEN_A=<token> bash update-skills.sh --all --dry-run`
4. 脚本自动完成：
   - 克隆上游最新版本到临时目录
   - diff 对比本地与上游的差异
   - 备份本地修改文件到 `~/.openclaw/workspace/.skill-backups/`
   - 应用上游更新
   - 自动恢复无冲突的本地修改
   - 标记需要手动合并的冲突文件
5. 更新后建议重启 Gateway：`openclaw gateway restart`

**关键机制**：
- 纯本地修改（上游没改的文件）→ 自动恢复
- 冲突文件（本地和上游都改了）→ 保留上游版本，本地备份到 `.skill-backups/`
- 每次更新生成 `UPDATE_REPORT.md`（变更清单 + 合并命令）

## Cron Jobs 说明

| 任务 | 计划（Asia/Shanghai）| 推送目标 |
|------|---------------------|---------|
| nightly-security-audit | 每天 03:00 | 飞书私聊 → 用户 |
| nightly-os-upgrade | 每天 04:00 | 飞书系统运维群 |

- **注册方式**：脚本输出提示，由安装后的 Agent 通过 `cron` 工具注册（isolated + agentTurn）
- **本地安装**：Agent 读取脚本输出提示后自动完成注册
- **远程安装**：目标机器的 Agent 在启动后自动完成注册
