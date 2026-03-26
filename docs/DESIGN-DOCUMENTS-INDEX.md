# OML Qwen 设计文档索引

本索引汇总了所有本地设计文档，涵盖 Qwen Code 架构、配置、命令、工具、扩展等完整技术分析。

---

## 核心设计文档

### 1. OML-QWEN-DEEP-DESIGN.md (14KB)
**OML Qwen 控制器深度设计文档**

基于官方文档和源码分析的完整设计。

**内容覆盖**:
- Qwen Code 官方架构分析 (packages/cli, packages/core)
- 数据流和命令处理机制
- 配置系统 (6 层优先级，完整配置选项)
- 命令系统 (官方内置命令，自定义命令)
- 扩展系统 (结构，配置，管理命令)
- OML Qwen 控制器设计 (完整命令树)
- 命令映射 (qwenx → oml qwen)
- Profile 系统
- 树形菜单帮助系统
- 实现方案 (核心模块代码示例)

**参考官方资源**:
- qwenlm.github.io/qwen-code-docs/
- GitHub: QwenLM/qwen-code
- zdoc configuration docs

---

### 2. OML-QWEN-CONTROLLER.md (5KB)
**OML Qwen 控制器设计方案**

**内容覆盖**:
- 架构设计图
- 完整命令树 (chat, session, config, keys, mcp, extensions, migrate)
- 树形菜单帮助系统设计
- Profile 配置管理系统
- qwenx 命令迁移映射表

---

### 3. QWENX-DATA-STRUCTURE.md (4KB)
**Qwenx 配置文件和数据存储树**

**内容覆盖**:
- qwenx fakehome 完整目录结构
- 配置文件详解 (settings.json, sessions, secrets)
- 数据流向图
- 配置隔离级别
- 迁移到 OML Qwen 控制器的映射

---

### 4. FAKEHOME-STRATEGY.md (3KB)
**Fakehome 策略文档**

**内容覆盖**:
- Fakehome 背景和设计目的
- 嵌套 Fakehome 问题
- 当前解决方案 (自动检测与修复，清理脚本)
- 目录结构 (正常结构 vs 嵌套结构)
- 未来改进方向 (环境变量传递，统一配置目录，容器化隔离)
- 最佳实践

---

## 实现指南

### 5. OML-INSTALLER-PLAN.md (7KB)
**OML 安装器设计方案**

### 6. OML-INSTALLER-COMPLETE.md (6KB)
**OML 安装器完整实现**

---

## 配置指南

### 7. QWENX-CONFIG-GUIDE.md (4KB)
**Qwenx 配置指南**

### 8. QWEN-KEY-SWITCHER-GUIDE.md (4KB)
**Qwen API Key 切换器指南**

### 9. QWEN-OAUTH-SWITCHER-GUIDE.md (5KB)
**Qwen OAuth 切换器指南**

### 10. QWEN-SWITCHER-COMPARISON.md (5KB)
**Qwen 切换器对比**

---

## 部署指南

### 11. ARCH-QWENX-REDEPLOY-PROMPT.md (8KB)
**Arch Linux Qwenx 重新部署指南**

### 12. UPDATE-QWENX-GUIDE.md (5KB)
**更新 Qwenx 指南**

---

## 文档覆盖范围总结

### 架构分析 ✅
- [x] Qwen Code 官方包结构
- [x] 数据流和命令处理机制
- [x] 配置系统层级
- [x] 扩展系统架构

### 配置系统 ✅
- [x] 6 层配置文件优先级
- [x] 完整配置选项列表 (GENERAL, OUTPUT, UI, MODEL, TOOLS, MCP 等)
- [x] 环境变量完整列表
- [x] .env 文件加载顺序

### 命令系统 ✅
- [x] 官方内置斜杠命令
- [x] @ 命令 (文件注入)
- [x] ! 命令 (Shell 执行)
- [x] 自定义命令系统
- [x] 快捷键

### 工具系统 ✅
- [x] 文件系统工具 (read_file, write_file, edit, list_directory, glob, grep_search)
- [x] Shell 工具 (run_shell_command, is_background 参数设计)
- [x] 安全与确认机制
- [x] 沙箱隔离

### MCP 系统 ✅
- [x] 传输方式 (http, sse, stdio)
- [x] 配置示例
- [x] 管理命令
- [x] 安全与控制

### 扩展系统 ✅
- [x] 扩展结构
- [x] qwen-extension.json 配置
- [x] 安装来源 (Claude Code, Gemini CLI, Git, 本地)
- [x] 扩展管理命令
- [x] 设置管理

### OML Qwen 控制器设计 ✅
- [x] 完整命令树
- [x] qwenx → oml qwen 命令映射
- [x] Profile 系统
- [x] 树形菜单帮助系统
- [x] 实现方案代码示例

### Fakehome 策略 ✅
- [x] 嵌套检测与修复
- [x] 清理脚本
- [x] 未来改进方向

---

## 云端资源参考

### 官方文档
- [Qwen Code 官方文档](https://qwenlm.github.io/qwen-code-docs/)
- [架构文档](https://qwenlm.github.io/qwen-code-docs/zh/developers/architecture/)
- [命令文档](https://qwenlm.github.io/qwen-code-docs/en/users/features/commands/)
- [MCP 文档](https://qwenlm.github.io/qwen-code-docs/en/users/features/mcp/)
- [扩展系统](https://qwenlm.github.io/qwen-code-docs/en/users/extension/introduction/)
- [配置文档](https://www.zdoc.app/en/QwenLM/qwen-code/blob/main/docs/cli/configuration.md)
- [工具文档](https://qwenlm.github.io/qwen-code-docs/en/developers/tools/introduction/)
- [Shell 工具](https://qwenlm.github.io/qwen-code-docs/en/developers/tools/shell/)
- [文件系统工具](https://qwenlm.github.io/qwen-code-docs/en/developers/tools/file-system/)

### GitHub 资源
- [Qwen Code GitHub](https://github.com/QwenLM/qwen-code)
- [Qwen Code Action](https://github.com/QwenLM/qwen-code-action)

### 其他资源
- [阿里云文档](https://help.aliyun.com/zh/model-studio/qwen-code)
- [Qwen Code Weekly](https://qwenlm.github.io/qwen-code-docs/en/blog/)

---

## 本地资料完整性评估

### 已完整覆盖的内容 ✅
1. **架构设计**: 官方包结构、数据流、命令处理
2. **配置系统**: 完整配置选项、环境变量、配置文件层级
3. **命令系统**: 所有内置命令、自定义命令、快捷键
4. **工具系统**: 文件系统工具、Shell 工具、安全机制
5. **MCP 系统**: 传输方式、配置示例、管理命令
6. **扩展系统**: 结构、配置、安装、管理
7. **OML Qwen 控制器**: 命令树、Profile 系统、帮助系统

### 可能需要补充的内容 📋
1. **Hooks 系统**: 官方 v0.12.0 新增功能，需进一步调研
2. **会话管理详细实现**: 官方文档中部分页面 404，需从源码获取
3. **扩展开发详细指南**: 官方文档中部分页面 404，需从源码获取
4. **Telemetry 系统**: 需进一步调研实现细节

---

## 下一步行动

### 高优先级 🔴
1. 实现 OML Qwen 控制器核心功能
2. 实现 Profile 配置管理系统
3. 实现树形菜单帮助系统

### 中优先级 🟡
1. 调研 Hooks 系统实现
2. 调研会话管理详细实现
3. 调研扩展开发详细指南

### 低优先级 🟢
1. Telemetry 系统调研
2. 更多官方源码分析

---

**文档更新时间**: 2026 年 3 月 26 日
**总文档数**: 57 个 Markdown 文件
**Qwen 相关文档**: 14 个核心设计文档
