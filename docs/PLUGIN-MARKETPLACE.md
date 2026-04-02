# OML 插件市场

**Version**: 1.0  
**Date**: 2026-04-01  
**Total Plugins**: 40

---

## 插件分类

### Agents (3)

| 插件 | 描述 | 状态 |
|------|------|------|
| qwen | Qwen AI 代理 - 支持对话、会话管理、Hooks | ✅ TypeScript |
| build | 构建自动化代理 - 运行构建和测试 | ✅ TypeScript |
| plan | 任务规划代理 - 创建和管理计划 | ✅ TypeScript |

### Subagents (12)

| 插件 | 描述 | 状态 |
|------|------|------|
| librarian | 文档搜索和知识编译 | ✅ TypeScript |
| reviewer | 代码审查和安全审计 | ✅ TypeScript |
| scout | 代码分析和依赖映射 | ✅ TypeScript |
| worker | 并行任务执行 | ✅ TypeScript |
| architect | 架构分析和改进建议 | ✅ TypeScript |
| debugger | Bug 查找和堆栈跟踪分析 | ✅ TypeScript |
| documenter | 文档生成 | ✅ TypeScript |
| optimizer | 代码优化建议 | ✅ TypeScript |
| researcher | 研究和信息收集 | ✅ TypeScript |
| security-auditor | 安全审计 | ✅ TypeScript |
| tester | 测试生成和执行 | ✅ TypeScript |
| translator | 翻译和本地化 | ✅ TypeScript |

### MCPs (13)

| 插件 | 描述 | 状态 |
|------|------|------|
| context7 | Context7 文档查询 | ✅ TypeScript |
| grep-app | 自然语言代码搜索 | ✅ TypeScript |
| websearch | 网络搜索和引用检索 | ✅ TypeScript |
| filesystem | 文件系统操作 | ✅ TypeScript |
| git | Git 操作 | ✅ TypeScript |
| weather | 天气数据查询 | ✅ TypeScript |
| translation | 翻译服务 | ✅ TypeScript |
| notification | 通知服务 | ✅ TypeScript |
| browser | 浏览器自动化 | ✅ TypeScript |
| calendar | 日历服务 | ✅ TypeScript |
| database | 数据库操作 | ✅ TypeScript |
| email | 邮件服务 | ✅ TypeScript |
| news | 新闻聚合 | ✅ TypeScript |

### Skills (12)

| 插件 | 描述 | 状态 |
|------|------|------|
| code-review | 代码审查 | ✅ TypeScript |
| security-scan | 安全扫描 | ✅ TypeScript |
| test-coverage | 测试覆盖率分析 | ✅ TypeScript |
| documentation-gen | 文档生成 | ✅ TypeScript |
| performance-analysis | 性能分析 | ✅ TypeScript |
| backup-setup | 备份配置 | ✅ TypeScript |
| best-practices | 最佳实践检查 | ✅ TypeScript |
| chaos-testing | 混沌测试 | ✅ TypeScript |
| ci-cd-setup | CI/CD 管道设置 | ✅ TypeScript |
| dependency-check | 依赖检查 | ✅ TypeScript |
| docker-setup | Docker 配置 | ✅ TypeScript |
| error-handling | 错误处理分析 | ✅ TypeScript |
| k8s-setup | Kubernetes 设置 | ✅ TypeScript |
| logging-setup | 日志配置 | ✅ TypeScript |
| mutation-testing | 突变测试 | ✅ TypeScript |
| performance-tuning | 性能优化 | ✅ TypeScript |
| refactor-suggest | 重构建议 | ✅ TypeScript |

---

## 使用指南

### 列出所有插件

```bash
# 列出所有插件
oml plugin list

# 按类型过滤
oml plugin list --type agent
oml plugin list --type subagent
oml plugin list --type mcp
oml plugin list --type skill

# 显示迁移状态
oml plugin migrated
```

### 安装插件

```bash
# 从本地路径安装
oml plugin install ./my-plugin

# 安装并启用
oml plugin install ./my-plugin --enable
```

### 管理插件

```bash
# 启用插件
oml plugin enable qwen

# 禁用插件
oml plugin disable qwen

# 卸载插件
oml plugin uninstall qwen

# 查看插件信息
oml plugin info qwen
```

### 运行插件

```bash
# 运行插件
oml plugin run qwen

# 带参数运行
oml plugin run build -- --verbose
```

---

## 开发者指南

### 创建插件

```bash
# 使用模板创建
mkdir -p packages/plugins/agents/my-agent
cd packages/plugins/agents/my-agent

# 创建必要文件
# - src/agent.ts
# - src/types.ts
# - src/index.ts
# - tests/agent.test.ts
# - package.json
# - plugin.json
# - tsconfig.json
# - vitest.config.ts
# - README.md
```

### 插件模板

```typescript
// src/agent.ts
export class MyAgent {
  public readonly name = 'my-agent';
  public readonly version = '1.0.0';
  
  async initialize(config: Record<string, unknown>): Promise<void> {
    // 初始化逻辑
  }
  
  async shutdown(): Promise<void> {
    // 清理逻辑
  }
  
  async process(message: AgentMessage): Promise<AgentResponse> {
    // 处理消息
    return { success: true, content: 'Response' };
  }
}
```

### 发布插件

1. 将插件放入 `packages/plugins/<type>/<name>/`
2. 更新 `packages/plugins/tsconfig.json`
3. 运行测试：`npm test`
4. 提交并打标签

---

## 统计

- **总插件数**: 40
- **TypeScript 插件**: 40 (100%)
- **测试覆盖**: 240+ 测试
- **类型安全**: 100%

---

## 许可证

MIT License
