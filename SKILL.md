---
name: bootstrap-skills
description: 传米科技 OpenClaw 完整环境初始化工具 v3.0。一键完成：重复检测+安装16个基础技能、配置Cron Jobs、git-crypt加密openclaw.json、workspace实时备份。触发词："安装基础技能"、"初始化技能"、"bootstrap skills"、"新机器部署"。
---

# Bootstrap Skills v3.0

传米科技 OpenClaw 完整环境初始化工具。

## 执行阶段

| 阶段 | 内容 |
|------|------|
| 0 | 依赖检查与自动安装（git/git-crypt/gpg/inotifywait）|
| 1 | 重复技能检测 + 安装 16 个基础技能 |
| 2 | 部署 Cron 脚本 + 提示配置定时任务 |
| 3 | git-crypt 加密 + openclaw.json 软链接 |
| 4 | Git 仓库初始化 + inotify 实时同步服务 |

## Token 说明

| | Token A（技能下载）| Token B（workspace 备份）|
|--|--|--|
| 来源 | 传米科技提供 | 用户自己提供 |
| 用途 | 从 git.moguyn.cn 克隆技能 | auto-sync 长期推送备份 |
| 保存 | ❌ 不保存，安装后消失 | ✅ 保存到目标机器本地 |

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
ssh user@host 'bash -s' < ~/.openclaw/workspace/skills/bootstrap-skills/scripts/install-skills.sh
```

## Agent 调用指南

用户说"安装基础技能"、"初始化技能"、"新机器部署"时：
1. 询问是本地安装还是远程安装
2. 提醒准备好 Token A（传米科技提供）、Token B（Gitea 仓库 token）和 Tavily API Key（https://tavily.com 免费申请）
3. 执行脚本（脚本末尾会自动重启 Gateway）
4. 脚本执行完毕后，由 Agent 自动完成以下工作：
   - 检查各技能配置状态并展示给用户
   - 如用户已提供 Tavily API Key，Agent 将其写入配置
5. 将脚本输出中的"待 Agent 完成后"部分展示给用户
