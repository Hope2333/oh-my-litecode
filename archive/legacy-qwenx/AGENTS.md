# Project Agents for Qwen

该文件用于描述本项目推荐的代理分工，帮助 CLI 在复杂任务中更稳定地路由。

## Primary agents

- build: 默认实现代理，负责编码、修改、测试
- plan: 只读规划代理，负责拆解任务与风险分析

## Subagents

- reviewer: 代码质量审查（风格、一致性、可维护性）
- security-auditor: 安全审计（输入校验、依赖、密钥泄漏）
- doc-writer: 文档生成与改写（README、使用指南、迁移说明）
- oracle: 高质量只读顾问（复杂架构与关键决策复核）
- librarian: 代码库/文档检索与证据提取
- explore: 高速代码探索与定位
- multimodal-looker: 图像/PDF/图表内容提炼
- metis: 预规划顾问（隐含需求与失败点识别）
- momus: 方案评审（可验证性/可回滚性）
- atlas: 通用执行代理（常规实现）

## Routing guideline

- 需求不明确或改动面大：先走 `plan`
- 进入实现阶段：切到 `build`
- 提交前：调用 `reviewer` + `security-auditor`
- 对外说明：调用 `doc-writer`

## Gate-oriented workflow

- 变更前门禁：优先执行 `/safety-preflight`
- 叠加迁移：优先执行 `/migration-overlay`
- 收尾校验：执行 `validation-gate` + `release-check`

## Safety baseline

- 默认不写入 `$PREFIX`
- REALHOME 默认只读，项目目录内可按任务写入
- 兼容层文件保留，不覆盖不删除历史能力
