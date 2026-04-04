---
name: bootstrap-skills
description: 传米科技 OpenClaw 完整环境初始化工具 v3.0。一键完成：重复检测+安装16个基础技能、Cron Jobs注册（本地自动/远程提示）、git-crypt加密openclaw.json、workspace实时备份。触发词："安装基础技能"、"初始化技能"、"bootstrap skills"、"新机器部署"。
---

# Bootstrap Skills v3.0

传米科技 OpenClaw 完整环境初始化工具。

## 执行阶段

| 阶段 | 内容 |
|------|------|
| 0 | 依赖检查与自动安装（git/git-crypt/gpg/inotifywait）|
| 1 | 重复技能检测 + 安装 16 个基础技能 |
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

## 安装的技能（16 个）

### global skills（11 个）
agent-browser、feishu-send-file、find-skills、lobehub-skills-search-engine、mcporter、openclaw-skills-smart-agent-memory、self-improving-agent、skillhub-preference、tavily-search-pro、proactive-agent、feishu-approval

### workspace skills（5 个）
config-guardian、openclaw-cli、runesleo-systematic-debugging、safe-install、skill-vetter

## 用法

### 本地安装
```bash
bash ~/.openclaw/workspace/skills/bootstrap-skills/scripts/install-skills.sh
```

### SSH 远程安装
```bash
# 自动检测远程模式（SSH 连接），也可显式传入：
OC_INSTALL_MODE=remote ssh user@host 'bash -s' < \
  ~/.openclaw/workspace/skills/bootstrap-skills/scripts/install-skills.sh
```

### 环境变量（全部可选）

| 变量 | 用途 |
|------|------|
| `OC_TOKEN_A` | 技能下载 Token（直接使用，不保存）|
| `OC_GITEA_URL` | Gitea 服务器地址 |
| `OC_GITEA_USER` | Gitea 用户名 |
| `OC_GITEA_TOKEN` | Gitea Access Token |
| `OC_INSTALL_MODE` | `local` / `remote`（自动检测时可覆盖）|
| `TAVILY_API_KEY` | Tavily API Key |

## Agent 调用指南

用户说"安装基础技能"、"初始化技能"、"新机器部署"时：
1. 确认是本地安装还是远程安装（脚本会自动检测 SSH）
2. 提醒准备好：
   - **Token A**（传米科技提供）：技能下载
   - **Gitea Access Token**：具有创建仓库和推送权限（用户自己的 Gitea 服务器）
   - **Tavily API Key**（可选）：https://tavily.com 免费申请
3. 执行脚本
4. 脚本末尾自动重启 Gateway
5. 脚本执行完毕后，由 Agent 自动完成：
   - 检查各技能配置状态并展示
   - 如提供了 Tavily API Key，写入配置
6. 将"待完成后"部分展示给用户

## Cron Jobs 说明

| 任务 | 计划（Asia/Shanghai）| 推送目标 |
|------|---------------------|---------|
| nightly-security-audit | 每天 03:00 | 飞书私聊 → 老板 |
| nightly-os-upgrade | 每天 04:00 | 飞书系统运维群 |

- **本地安装**：脚本自动通过 `openclaw cron add` 注册
- **远程安装**：脚本打印注册命令，**需人工在目标机器上执行**（推送远程后告知）
