# Compatibility Notes

本目录采用“官方原生 + 兼容叠加层”并存模式。

## 官方原生优先
- settings: `.qwen/settings.json`（含 `mcpServers`）
- skills: `.qwen/skills/*/SKILL.md`（YAML frontmatter）
- agents: `.qwen/agents/*.md`（YAML frontmatter）
- commands: `.qwen/commands/*.md`
- extensions: `.qwen/extensions/*/qwen-extension.json`

## 第二轮映射（将兼容约束转为可执行入口）
- 路径与权限边界：`/safety-preflight` + `path-safety-check`
- 迁移编排：`/migration-overlay` + `safe-migration`
- 收尾校验：`validation-gate` + `release-check`
- 敏感信息防护：`secrets-guard`

## forAI/opencode 提炼来源（只读）
- `forAI/extracted/opencode/opencode.json`
- `forAI/extracted/opencode/oh-my-opencode.json`
- `forAI/extracted/opencode/oh-my-opencode-hybrid.json`
- `forAI/extracted/opencode/README.md`
- `forAI/extracted/opencode/best-practices.md`
- `forAI/extracted/qwen-code/.../extensions/examples/*/qwen-extension.json`

## 兼容叠加层（保留旧内容，不删除）
- `mcp.servers`（历史字段，保留以兼容旧习惯）
- `.qwen/commands/registry.json`
- `.qwen/hooks/policy.json`
- `.qwen/policies/safety.json`
- `.qwen/workflows/layered-migration.md`
- `.qwen/extensions/sample-extension/manifest.json`

## 非官方字段迁移策略（避免 settings 告警）
为兼容官方解析器，以下字段不再放入 `.qwen/settings.json`：
- `taskCategories`
- `agentRouting`
- `executionPolicy`
- `insightSources`

这些字段已迁移至 `.qwen/compat.layer.json`，用于保留叠加能力且不触发 Unknown setting 警告。

## 外部 MCP 兼容层
- 合并脚本：`.qwen/scripts/mcp_merge_loader.py`
- Schema 校验脚本：`.qwen/scripts/mcp_schema_lint.py`
- 健康检查脚本：`.qwen/scripts/mcp_health_check.py`
- 一键门禁脚本：`.qwen/scripts/mcp_sync_external.py`
- 调用桥脚本：`.qwen/scripts/mcp_call_bridge.py`
- 调用桥文档：`.qwen/research/mcp-bridge-schema.md`
- 输入来源：`.qwen/settings.json`、`.mcp.json`、`.claude/.mcp.json`
- 汇总输出：`.qwen/generated.mcp.json`、`.qwen/mcp-schema-lint-report.json`、`.qwen/mcp-health-report.json`、`.qwen/mcp-sync-report.json`、`.qwen/mcp-call-report.json`
- 合并优先级：`settings > project > claude`

## 使用建议
1. 新增能力优先使用官方原生结构。
2. 旧字段仅保留兼容，不作为新增能力首选。
3. 每次叠加后执行 JSON/文件存在性校验。
4. 优先通过 commands/skills 落地“策略”，减少不可执行文档配置。
5. 使用 `.qwen/scripts/mcp_health_check.py` 做 MCP 可达性基线检查。
