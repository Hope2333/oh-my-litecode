# OML API 参考文档

**版本**: 0.2.0  
**日期**: 2026-03-23

---

## 📖 概述

OML (Oh My Litecode) 是一个插件化的 AI 辅助开发工具链管理器。

---

## 🎯 核心命令

### oml (主命令)

```bash
oml <command> [options]
```

**子命令**:

| 命令 | 说明 | 示例 |
|------|------|------|
| `build` | 构建项目 | `oml build --project opencode --target termux-dpkg` |
| `hotfix` | 管理热修复 | `oml hotfix list` |
| `doc` | 查看文档 | `oml doc opencode` |
| `opencode` | OpenCode 管理 | `oml opencode diagnose` |
| `plugins` | 插件管理 | `oml plugins list` |
| `worker` | 子代理执行 | `oml worker spawn` |
| `qwen` | Qwenx 部署 | `oml qwen deploy` |
| `install` | 安装 OML | `oml install` |
| `update` | 更新 OML | `oml update all` |
| `supertui` | TUI 界面 | `oml supertui` |
| `cloud` | 云同步 | `oml cloud sync pull` |
| `perf` | 性能工具 | `oml perf benchmark` |

---

## 🔌 插件命令

### MCP 服务

```bash
oml mcp <name> <command>
```

**可用 MCP**:

| MCP | 命令 | 说明 |
|-----|------|------|
| `context7` | `query` | 文档查询 |
| `grep-app` | `search` | 代码搜索 |
| `websearch` | `search` | 网络搜索 |
| `filesystem` | `read/write/list` | 文件操作 |
| `git` | `status/diff/commit` | Git 操作 |
| `browser` | `navigate/screenshot` | 浏览器自动化 |
| `database` | `connect/query` | 数据库操作 |
| `notification` | `send_desktop/send_email` | 通知推送 |
| `calendar` | `list_events/add_event` | 日历管理 |
| `email` | `send/list/read` | 邮件管理 |
| `translation` | `translate_text` | 翻译服务 |
| `weather` | `get_weather/get_forecast` | 天气服务 |
| `news` | `get_news/get_headlines` | 新闻服务 |

### Subagents

```bash
oml subagent <name> <command>
```

**可用 Subagents**:

| Subagent | 命令 | 说明 |
|----------|------|------|
| `worker` | `spawn/status` | 并行任务执行 |
| `scout` | `explore/analyze` | 代码探测 |
| `librarian` | `search/retrieve` | 文档检索 |
| `reviewer` | `review/audit` | 代码审查 |
| `researcher` | `search_web/compile_report` | 信息调研 |
| `tester` | `generate_tests/run_tests` | 测试生成 |
| `documenter` | `generate_docs/update_readme` | 文档生成 |
| `optimizer` | `analyze_performance/apply_fixes` | 代码优化 |
| `translator` | `translate_text/translate_docs` | 翻译 |
| `debugger` | `find_bugs/suggest_fixes` | 调试 |
| `architect` | `analyze_architecture/suggest_improvements` | 架构设计 |
| `security-auditor` | `audit_code/find_vulnerabilities` | 安全审计 |

### Skills

```bash
oml skill <name> <command>
```

**可用 Skills**:

| Skill | 命令 | 说明 |
|-------|------|------|
| `code-review` | `review_code/check_style` | 代码审查 |
| `security-scan` | `scan_vulnerabilities/suggest_fixes` | 安全扫描 |
| `performance-analysis` | `analyze_performance/identify_bottlenecks` | 性能分析 |
| `dependency-check` | `check_dependencies/find_updates` | 依赖检查 |
| `test-coverage` | `analyze_coverage/suggest_tests` | 测试覆盖 |
| `documentation-gen` | `generate_api_docs/generate_readme` | 文档生成 |
| `refactor-suggest` | `analyze_code/suggest_refactoring` | 重构建议 |
| `best-practices` | `check_best_practices/suggest_improvements` | 最佳实践 |
| `error-handling` | `check_error_handling/suggest_fixes` | 错误处理 |
| `logging-setup` | `setup_logging/check_logging` | 日志设置 |
| `ci-cd-setup` | `setup_ci/setup_cd` | CI/CD 设置 |
| `docker-setup` | `setup_docker/create_dockerfile` | Docker 设置 |
| `k8s-setup` | `setup_k8s/create_manifest` | K8s 设置 |
| `monitoring-setup` | `setup_monitoring/configure_alerts` | 监控设置 |
| `backup-setup` | `setup_backup/configure_schedule` | 备份设置 |
| `security-hardening` | `harden_system/audit_security` | 安全加固 |
| `performance-tuning` | `tune_performance/optimize_config` | 性能调优 |
| `code-coverage` | `analyze_coverage/generate_report` | 代码覆盖 |
| `mutation-testing` | `run_mutation/analyze_results` | 变异测试 |
| `chaos-testing` | `run_chaos/analyze_resilience` | 混沌测试 |

---

## 🔧 环境变量

| 变量 | 说明 | 默认值 |
|------|------|-------|
| `OML_ROOT` | OML 安装目录 | `~/develop/oh-my-litecode` |
| `QWEN_OAUTH_DIR` | Qwen OAuth 存储目录 | `~/.oml/qwen-oauth` |
| `QWEN_KEY_DIR` | Qwen Key 存储目录 | `~/.oml/qwen-keys` |
| `CLOUD_API` | 云 API 地址 | `https://api.oml.dev` |

---

## 📚 配置文件

### 主配置

**位置**: `~/.oml/config.json`

```json
{
  "version": "0.2.0",
  "installed_at": "2026-03-23T10:00:00+08:00",
  "branch": "main",
  "system": "termux"
}
```

### 云同步配置

**位置**: `~/.oml/sync-config.json`

```json
{
  "enabled": true,
  "auto_sync": false,
  "sync_interval": 3600,
  "conflict_resolution": "ask",
  "last_sync": null
}
```

---

## 🔗 相关文档

- [安装指南](INSTALL-GUIDE.md)
- [更新指南](UPDATE-GUIDE.md)
- [插件开发指南](PLUGIN-DEV-GUIDE.md)
- [MCP 开发指南](MCP-DEV-GUIDE.md)

---

**维护者**: OML Team  
**版本**: 0.2.0
