# Bootstrap Skills

传米科技 OpenClaw 完整环境初始化工具 v3.1

一条命令，完成新机器的全部 AI 助手环境搭建。

---

## 🚀 这个工具能做什么

### 安装 14 个核心技能

| 类别 | 技能 | 安装类型 |
|------|------|:---------:|
| 🌐 网络与搜索 | Tavily Search Pro | 全局 |
| 🌐 网络与搜索 | Agent Browser | 全局 |
| 📁 文件与协作 | 飞书文件发送 | 全局 |
| 📁 文件与协作 | 飞书审批发起 | 全局 |
| 🔍 技能管理 | 技能搜索 / 市场 / 安全审查 / 安全安装 | 全局+工作区 |
| 🛠️ 系统运维 | OpenClaw CLI | 工作区 |
| 🛠️ 系统运维 | 配置文件保护 | 工作区 |
| 🛠️ 系统运维 | MCP 服务器管理 | 全局 |
| 🛠️ 系统运维 | 系统化调试 | 工作区 |
| 🤝 主动协作 | 主动行为框架 | 全局 |

> 全局技能安装在 `~/.openclaw/skills/`，所有 Agent 共享；工作区技能安装在 `~/.openclaw/workspace/skills/`，仅当前工作区可用。

### 自动配置的插件

| 插件 | 说明 |
|------|------|
| **Dreaming (memory-core)** | 三阶段记忆整理（Light→REM→Deep），每天 04:30 自动运行 |
| **Memory-Wiki** | Bridge 模式联动 Dreaming，vault 存储在 ~/.openclaw/wiki/main，兼容 Obsidian |

### 自动完成的环境配置

- **工作区加密**：敏感配置文件自动加密，推送远程也安全
- **自动备份**：工作区变更实时同步到 Gitea 私有仓库，不丢数据
- **定时任务准备**：安全巡检和系统升级脚本就绪
- **Dreaming 记忆整理**：三阶段记忆整理（Light→REM→Deep），自动将短期记忆转为长期知识
- **Memory-Wiki 编译**：持久记忆自动编译为结构化知识库，兼容 Obsidian 格式

---

## 📋 安装前需要准备的信息

| 信息 | 说明 | 是否必须 |
|------|------|:--------:|
| **Token A（技能下载）** | 传米科技提供，仅用于本次下载，不保存 | ✅ 必须 |
| **Gitea 服务器地址** | 默认 `https://git.moguyn.cn`，可直接回车 | 可选 |
| **Gitea 用户名** | Gitea 登录账号名 | 与 Token 配套 |
| **Gitea Access Token** | Gitea → 设置 → 应用中生成，需要仓库读写权限 | 与账号配套 |
| **Tavily API Key** | 从 https://tavily.com 免费申请 | 可选 |

> 💡 Gitea Access Token 安全写入本机，不会在屏幕上明文显示。

---

## ⚙️ 安装后还需手动完成

1. **配置 2 个定时任务**（在 OpenClaw 中操作）
   - 每天凌晨 3 点 — 安全巡检
   - 每天凌晨 4 点 — 系统升级

2. **完成飞书 OAuth 授权**（在飞书对话框操作）
   - 飞书文件发送、飞书审批发起 需要授权才能使用

---

## 🔧 运行方式

**本地运行：**
```bash
bash ~/.openclaw/workspace/skills/bootstrap-skills/scripts/install-skills.sh
```

**SSH 远程安装：**
```bash
ssh user@host 'bash -s' < ~/.openclaw/workspace/skills/bootstrap-skills/scripts/install-skills.sh
```

---

## 🔒 安全说明

- Token A 仅用于本次下载，安装结束后不保留
- Gitea Access Token 仅保存在本机，用于工作区自动同步
- 敏感配置通过 git-crypt 加密，仓库泄露也不影响安全
- 所有技能安装前均经过安全审计

---

*传米科技出品 · 让 AI 真正为你所用*
