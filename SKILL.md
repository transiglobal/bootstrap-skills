---
name: bootstrap-skills
description: 传米科技 OpenClaw 基础技能一键安装器。在新机器部署 OpenClaw 后，运行此技能可批量安装所有18个基础技能。支持本地安装和 SSH 远程安装。触发词："安装基础技能"、"初始化技能"、"bootstrap skills"、"新机器部署"。
---

# Bootstrap Skills

传米科技 OpenClaw 基础技能一键安装器。

## 使用场景

- 新机器部署 OpenClaw 后，快速恢复所有基础技能
- 通过 SSH 远程初始化服务器上的 OpenClaw 技能环境

## 安装的技能列表（18个）

### workspace skills（~/.openclaw/workspace/skills/）
- agent-browser
- config-guardian
- elatia-humanizer-zh
- feishu-send-file
- find-skills
- lobehub-skills-search-engine
- mcporter
- narrative-voice
- openclaw-cli
- smart-agent-memory
- runesleo-systematic-debugging
- safe-install
- self-improving-agent
- skill-vetter
- skillhub-preference
- tavily-search-pro
- proactive-agent

### global skills（~/.openclaw/skills/）
- feishu-approval

## 用法

### 本地安装

```bash
bash ~/.openclaw/workspace/skills/bootstrap-skills/scripts/install-skills.sh
```

### SSH 远程安装

```bash
ssh user@remote-host 'bash -s' < ~/.openclaw/workspace/skills/bootstrap-skills/scripts/install-skills.sh
```

### 通过 curl 安装（无需本地文件）

```bash
curl -fsSL https://raw.githubusercontent.com/transiglobal/bootstrap-skills/main/scripts/install-skills.sh | bash
```

## Agent 调用指南

当用户说"安装基础技能"、"初始化技能"、"新机器部署"时：

1. 询问是本地安装还是远程 SSH 安装
2. 本地安装：直接执行脚本
3. 远程安装：询问 SSH 连接信息（user@host），然后执行远程命令
4. 安装完成后提示用户重启 OpenClaw 会话

## 注意事项

- 需要能访问 github.com（国内可能需要代理）
- 已存在的技能会自动跳过，不会覆盖
- 安装完成后需重启 OpenClaw 会话才能加载新技能
