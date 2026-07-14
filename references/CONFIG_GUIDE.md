# 技能配置指南

## 技能配置说明

### agent-browser
- **触发词**：无（工具类，由其他技能调用）
- **依赖**：Chrome/Chromium 浏览器

### config-guardian
- **触发词**：无（自动保护配置文件）

### elatia-humanizer-zh
- **触发词**："润色"、"改写"、"去 AI 味"、"更像人写的"

### feishu-send-file
- **触发词**："发送文件到飞书"、"上传文件"
- **依赖**：飞书 OAuth 授权

### find-skills
- **触发词**："找技能"、"安装技能"、"find-skill"

### lobehub-skills-search-engine
- **触发词**：无（由 find-skills 调用）

### mcporter
- **触发词**：无（MCP 服务器管理）
- **配置文件**：`~/.openclaw/config/mcp-servers.json`

### narrative-voice
- **触发词**：无（自动叙事风格）

### openclaw-cli
- **触发词**：无（CLI 参考手册）

### openclaw-skills-smart-agent-memory
- **触发词**：无（自动记忆管理）
- **依赖**：Node.js、SQLite

### runesleo-systematic-debugging
- **触发词**：无（调试框架）

### safe-install
- **触发词**："安装技能"、"安装 skill"、"装一个 skill"

### skill-vetter
- **触发词**：无（由 safe-install 调用）

### skillhub-preference
- **触发词**：无（技能市场偏好配置）

### tavily-search-pro
- **触发词**："搜索"、"查一下"、"web search"、"上网搜"
- **依赖**：Tavily API Key（环境变量 `TAVILY_API_KEY`）

### proactive-agent
- **触发词**：无（主动行为框架）

### feishu-approval
- **触发词**："发起审批"、"提交报销"、"我要请假"、"付款申请"
- **依赖**：飞书 OAuth 授权

---

## 定时任务管理

```bash
openclaw cron list                              # 查看所有任务
openclaw cron run <job-id>                      # 手动触发
```

## workspace 同步服务管理

```bash
systemctl --user status openclaw-sync-main.service    # 状态
systemctl --user restart openclaw-sync-main.service   # 重启
journalctl --user -u openclaw-sync-main.service -f    # 日志
```

## 常见问题

**Q: GPG 密钥丢失怎么办？**
A: 从 `~/gpg-backup/openclaw-gpg-private.asc` 恢复，或重新初始化 git-crypt。

**Q: openclaw.json 软链接异常？**
A: `rm ~/.openclaw/openclaw.json && mv ~/.openclaw/openclaw.json.before-git-crypt ~/.openclaw/openclaw.json`

**Q: 推送失败怎么办？**
A: 检查 Token B 是否有效：`cd ~/.openclaw/workspace && git push origin main`
