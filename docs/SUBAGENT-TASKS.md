# OML Subagent 执行清单

**版本**: 0.2.0  
**日期**: 2026-03-23  
**状态**: 🚀 执行中

---

## 🎯 Subagent 委托策略

为节省 context，将具体实现委托给专用 Subagent：

| Subagent | 职责 | 当前任务 |
|----------|------|---------|
| **atlas-mcp** | MCP 实现 | database, notification, calendar |
| **atlas-agent** | Subagent 实现 | researcher, tester, documenter |
| **atlas-skill** | Skills 实现 | code-review, security-scan |
| **build-test** | 测试编写 | 单元测试，集成测试 |
| **doc-api** | API 文档 | API 参考，命令文档 |
| **doc-guide** | 使用指南 | 故障排查，最佳实践 |

---

## 📋 Atlas-MCP Tasks (MCP 实现)

### P0 (今日)

- [ ] **database MCP**
  - 文件：`plugins/mcps/database/`
  - 命令：connect, query, insert, update, delete, list_tables
  - 测试：test-database-mcp.sh
  - 优先级：⭐⭐⭐⭐⭐

- [ ] **notification MCP**
  - 文件：`plugins/mcps/notification/`
  - 命令：send_desktop, send_email, send_webhook, list_channels
  - 测试：test-notification-mcp.sh
  - 优先级：⭐⭐⭐⭐⭐

### P1 (本周)

- [ ] **calendar MCP**
  - 文件：`plugins/mcps/calendar/`
  - 命令：list_events, add_event, remove_event, get_reminders
  - 测试：test-calendar-mcp.sh
  - 优先级：⭐⭐⭐

- [ ] **email MCP**
  - 文件：`plugins/mcps/email/`
  - 命令：send_email, list_emails, read_email, delete_email
  - 测试：test-email-mcp.sh
  - 优先级：⭐⭐⭐

### P2 (本月)

- [ ] **weather MCP**
  - 文件：`plugins/mcps/weather/`
  - 命令：get_weather, get_forecast, get_alerts
  - 优先级：⭐

- [ ] **news MCP**
  - 文件：`plugins/mcps/news/`
  - 命令：get_news, get_headlines, search_articles
  - 优先级：⭐

- [ ] **translation MCP**
  - 文件：`plugins/mcps/translation/`
  - 命令：translate_text, detect_language, get_languages
  - 优先级：⭐⭐

---

## 📋 Atlas-Agent Tasks (Subagent 实现)

### P0 (今日)

- [ ] **researcher Subagent**
  - 文件：`plugins/subagents/researcher/`
  - 命令：search_web, analyze_data, compile_report, find_sources
  - 测试：test-researcher.sh
  - 优先级：⭐⭐⭐⭐⭐

- [ ] **tester Subagent**
  - 文件：`plugins/subagents/tester/`
  - 命令：generate_tests, run_tests, report_coverage, fix_tests
  - 测试：test-tester.sh
  - 优先级：⭐⭐⭐⭐⭐

### P1 (本周)

- [ ] **documenter Subagent**
  - 文件：`plugins/subagents/documenter/`
  - 命令：generate_docs, update_readme, add_comments, check_docs
  - 测试：test-documenter.sh
  - 优先级：⭐⭐⭐⭐

- [ ] **optimizer Subagent**
  - 文件：`plugins/subagents/optimizer/`
  - 命令：analyze_performance, suggest_optimizations, apply_fixes
  - 测试：test-optimizer.sh
  - 优先级：⭐⭐⭐⭐

### P2 (本月)

- [ ] **translator Subagent**
  - 文件：`plugins/subagents/translator/`
  - 命令：translate_text, translate_docs, localize
  - 优先级：⭐⭐

- [ ] **debugger Subagent**
  - 文件：`plugins/subagents/debugger/`
  - 命令：find_bugs, analyze_stack_trace, suggest_fixes
  - 优先级：⭐⭐

- [ ] **architect Subagent**
  - 文件：`plugins/subagents/architect/`
  - 命令：analyze_architecture, suggest_improvements
  - 优先级：⭐

- [ ] **security-auditor Subagent**
  - 文件：`plugins/subagents/security-auditor/`
  - 命令：audit_code, find_vulnerabilities, report_issues
  - 优先级：⭐⭐⭐

---

## 📋 Atlas-Skill Tasks (Skills 实现)

### P0 (今日)

- [ ] **code-review Skill**
  - 文件：`plugins/skills/code-review/`
  - 命令：review_code, suggest_improvements, check_style
  - 测试：test-code-review.sh
  - 优先级：⭐⭐⭐⭐⭐

- [ ] **security-scan Skill**
  - 文件：`plugins/skills/security-scan/`
  - 命令：scan_vulnerabilities, report_issues, suggest_fixes
  - 测试：test-security-scan.sh
  - 优先级：⭐⭐⭐⭐⭐

### P1 (本周)

- [ ] **performance-analysis Skill**
  - 文件：`plugins/skills/performance-analysis/`
  - 命令：analyze_performance, identify_bottlenecks
  - 优先级：⭐⭐⭐⭐

- [ ] **dependency-check Skill**
  - 文件：`plugins/skills/dependency-check/`
  - 命令：check_dependencies, find_updates, audit_licenses
  - 优先级：⭐⭐⭐⭐

- [ ] **test-coverage Skill**
  - 文件：`plugins/skills/test-coverage/`
  - 命令：analyze_coverage, generate_report, suggest_tests
  - 优先级：⭐⭐⭐⭐

### P2 (本月)

- [ ] **documentation-gen Skill**
  - 文件：`plugins/skills/documentation-gen/`
  - 命令：generate_api_docs, generate_readme
  - 优先级：⭐⭐⭐

- [ ] **refactor-suggest Skill**
  - 文件：`plugins/skills/refactor-suggest/`
  - 命令：analyze_code, suggest_refactoring
  - 优先级：⭐⭐⭐

- [ ] **best-practices Skill**
  - 文件：`plugins/skills/best-practices/`
  - 命令：check_best_practices, suggest_improvements
  - 优先级：⭐⭐⭐

---

## 📋 Build-Test Tasks (测试编写)

### MCP 测试

- [ ] filesystem MCP 测试套件
- [ ] git MCP 测试套件
- [ ] browser MCP 测试套件
- [ ] database MCP 测试套件
- [ ] notification MCP 测试套件

### Subagent 测试

- [ ] researcher Subagent 测试套件
- [ ] tester Subagent 测试套件
- [ ] documenter Subagent 测试套件

### Skills 测试

- [ ] code-review Skill 测试套件
- [ ] security-scan Skill 测试套件
- [ ] performance-analysis Skill 测试套件

### 集成测试

- [ ] MCP 间协作测试
- [ ] Subagent 间协作测试
- [ ] Skills 集成测试
- [ ] 端到端测试

---

## 📋 Doc-API Tasks (API 文档)

### 命令文档

- [ ] 所有 oml 命令文档
- [ ] 所有 MCP 命令文档
- [ ] 所有 Subagent 命令文档
- [ ] 所有 Skills 命令文档

### API 参考

- [ ] API 设计原则
- [ ] 参数说明
- [ ] 返回值说明
- [ ] 错误码说明
- [ ] 示例代码

### 插件 API

- [ ] 插件开发 API
- [ ] MCP 开发 API
- [ ] Subagent 开发 API
- [ ] Skills 开发 API

---

## 📋 Doc-Guide Tasks (使用指南)

### 用户指南

- [ ] 快速入门 (更新)
- [ ] 最佳实践
- [ ] 故障排查
- [ ] 常见问题

### 开发者指南

- [ ] 开发环境设置
- [ ] 代码规范
- [ ] 提交流程
- [ ] 发布流程

### 高级指南

- [ ] 性能调优
- [ ] 安全配置
- [ ] 扩展开发
- [ ] 插件市场

---

## 🎯 执行优先级

### 今日 (P0)

1. database MCP (atlas-mcp)
2. notification MCP (atlas-mcp)
3. researcher Subagent (atlas-agent)
4. tester Subagent (atlas-agent)
5. code-review Skill (atlas-skill)
6. security-scan Skill (atlas-skill)
7. API 参考框架 (doc-api)

### 本周 (P1)

1. calendar MCP (atlas-mcp)
2. documenter Subagent (atlas-agent)
3. performance-analysis Skill (atlas-skill)
4. 故障排查指南 (doc-guide)
5. 测试覆盖提升到 70% (build-test)

### 本月 (P2)

1. MCP 达到 10+ (atlas-mcp)
2. Subagents 达到 8+ (atlas-agent)
3. Skills 达到 5+ (atlas-skill)
4. 文档完整度 90% (doc-api, doc-guide)

---

## 📊 进度追踪

| 类别 | 待办 | 进行中 | 完成 | 进度 |
|------|------|--------|------|------|
| **MCP** | 7 | 0 | 6 | 46% |
| **Subagents** | 8 | 0 | 4 | 33% |
| **Skills** | 20 | 0 | 0 | 0% |
| **测试** | 20 | 0 | 5 | 20% |
| **文档** | 12 | 0 | 18 | 60% |

---

## ✅ 验收标准

### 代码质量

- [ ] 所有代码通过 lint
- [ ] 测试覆盖率 >80%
- [ ] 无严重安全漏洞
- [ ] 性能指标达标

### 文档质量

- [ ] API 文档完整
- [ ] 使用指南清晰
- [ ] 示例代码可运行
- [ ] 文档覆盖率 >90%

---

**维护者**: OML Team  
**版本**: 0.2.0  
**下次更新**: 2026-03-24
