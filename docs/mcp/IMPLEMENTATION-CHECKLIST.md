# MCP 实施检查清单 | Implementation Checklist

> **版本**: 1.0.0 | **标签**: [GENERIC] [PLANNING]

---

## 📋 概述

本文档提供 Qwen Code 递归子代理架构的完整实施检查清单，包含 Phase 1-5 的所有任务、验收标准和依赖关系。

---

## Phase 1：基础实现（2-3 天）⭐⭐⭐⭐⭐

### 任务清单

| ID | 任务 | 优先级 | 预计工时 | 状态 |
|----|------|--------|----------|------|
| 1.1 | 会话 ID 编码工具 | P0 | 2 小时 | ⏳ |
| 1.2 | 环境变量注入脚本 | P0 | 4 小时 | ⏳ |
| 1.3 | MCP 递归检测器 | P0 | 4 小时 | ⏳ |
| 1.4 | 基础测试脚本 | P0 | 4 小时 | ⏳ |

---

### 任务 1.1：会话 ID 编码工具

**文件**: `~/.qwen/scripts/session_id_encode.sh`

**验收标准**:
- [ ] 能生成 22 字符 Base64URL 编码
- [ ] 随机性测试通过
- [ ] 支持命令行调用

**依赖**: 无

**实施步骤**:
1. 创建脚本文件
2. 实现 Base64URL 编码逻辑
3. 添加命令行参数解析
4. 编写单元测试

**测试命令**:
```bash
# 生成 100 个 ID 检查唯一性
for i in {1..100}; do
  ~/.qwen/scripts/session_id_encode.sh --generate
done | sort | uniq -c | awk '$1 > 1'

# 应无输出（无重复）
```

---

### 任务 1.2：环境变量注入脚本

**文件**: `~/.qwen/scripts/qwen-session-env.sh`

**验收标准**:
- [ ] 能正确设置所有环境变量
- [ ] 父子会话关系可追踪
- [ ] 清理函数正常工作

**依赖**: 任务 1.1

**实施步骤**:
1. 创建脚本文件
2. 实现 `start_root_session` 函数
3. 实现 `start_child_session` 函数
4. 实现 `cleanup_env` 函数
5. 添加错误处理

**测试命令**:
```bash
# 测试根会话
source ~/.qwen/scripts/qwen-session-env.sh
start_root_session
echo $QWEN_SESSION_ID  # 应输出 22 字符

# 测试子会话
start_child_session "reviewer" "test-task"
echo $QWEN_PARENT_SESSION  # 应等于根会话 ID
```

---

### 任务 1.3：MCP 递归检测器

**文件**: `~/.qwen/scripts/mcp_session_guard.py`

**验收标准**:
- [ ] MCP 环境正确检测
- [ ] 递归调用被阻止
- [ ] 错误信息清晰

**依赖**: 任务 1.2

**实施步骤**:
1. 创建 Python 脚本
2. 实现 `detect_mcp_context` 函数
3. 实现 `check_recursion_safety` 函数
4. 添加 JSON 输出

**测试命令**:
```bash
# 测试检测
python3 ~/.qwen/scripts/mcp_session_guard.py

# 应输出：{"allowed": true, "reason": "允许"}
```

---

### 任务 1.4：基础测试脚本

**文件**: `~/.qwen/scripts/test_session_mgmt.sh`

**验收标准**:
- [ ] 覆盖所有核心功能
- [ ] 测试通过率 100%
- [ ] 提供详细测试报告

**依赖**: 任务 1.1-1.3

**实施步骤**:
1. 创建测试脚本
2. 编写测试用例
3. 实现测试报告生成
4. 运行测试并修复问题

**测试用例**:
```bash
# 1. 会话 ID 生成测试
test_session_id_generation() {
  local id=$(~/.qwen/scripts/session_id_encode.sh --generate)
  [[ ${#id} -eq 22 ]] || return 1
  [[ $id =~ ^[A-Za-z0-9_.]{22}$ ]] || return 1
}

# 2. 环境变量设置测试
test_env_variables() {
  source ~/.qwen/scripts/qwen-session-env.sh
  start_root_session
  [[ -n "$QWEN_SESSION_ID" ]] || return 1
  [[ -z "$QWEN_PARENT_SESSION" ]] || return 1
  [[ "$QWEN_SESSION_DEPTH" -eq 0 ]] || return 1
}

# 3. 递归预防测试
test_recursion_prevention() {
  source ~/.qwen/scripts/qwen-session-env.sh
  start_root_session
  start_child_session "test" "task"
  
  # 尝试创建孙会话（应失败）
  if start_child_session "test2" "task2" 2>/dev/null; then
    return 1  # 不应成功
  fi
}
```

---

## Phase 2：递归预防（3-5 天）⭐⭐⭐⭐

### 任务清单

| ID | 任务 | 优先级 | 预计工时 | 状态 |
|----|------|--------|----------|------|
| 2.1 | MCP 检测器增强 | P0 | 4 小时 | ⏳ |
| 2.2 | 递归检查脚本 | P0 | 4 小时 | ⏳ |
| 2.3 | 深度限制实现 | P0 | 4 小时 | ⏳ |
| 2.4 | 集成测试 | P0 | 8 小时 | ⏳ |

---

### 任务 2.1：MCP 检测器增强

**文件**: `~/.qwen/scripts/mcp_detector.sh`

**验收标准**:
- [ ] 检测环境变量
- [ ] 检测配置文件
- [ ] 支持多重检测

**依赖**: 任务 1.3

**实施步骤**:
1. 创建脚本文件
2. 实现环境变量检测
3. 实现配置文件检测
4. 添加调试输出

---

### 任务 2.2：递归检查脚本

**文件**: `~/.qwen/scripts/recursion_guard.sh`

**验收标准**:
- [ ] 检查父会话存在
- [ ] 检查 MCP 环境
- [ ] 检查深度限制

**依赖**: 任务 2.1

**实施步骤**:
1. 创建脚本文件
2. 实现三条规则检查
3. 添加错误输出
4. 集成到会话启动流程

---

### 任务 2.3：深度限制实现

**文件**: `~/.qwen/scripts/depth_limit.sh`

**验收标准**:
- [ ] 深度追踪正确
- [ ] 达到限制时阻止
- [ ] 可配置最大深度

**依赖**: 任务 1.2

**实施步骤**:
1. 创建脚本文件
2. 实现深度计算
3. 实现限制检查
4. 添加配置选项

---

### 任务 2.4：集成测试

**文件**: `~/.qwen/scripts/test_recursion.sh`

**验收标准**:
- [ ] 测试所有递归场景
- [ ] 验证预防措施有效
- [ ] 提供测试报告

**依赖**: 任务 2.1-2.3

**测试场景**:
```bash
# 场景 1: 正常子会话创建
test_normal_child_session() {
  source ~/.qwen/scripts/qwen-session-env.sh
  start_root_session
  start_child_session "reviewer" "test"
  # 应成功
}

# 场景 2: 递归子会话（应失败）
test_recursive_session() {
  source ~/.qwen/scripts/qwen-session-env.sh
  start_root_session
  start_child_session "reviewer" "test"
  
  # 尝试创建孙会话
  if start_child_session "sub-reviewer" "sub-test" 2>/dev/null; then
    echo "FAIL: 递归会话不应成功"
    return 1
  fi
}

# 场景 3: MCP 环境下子会话（应失败）
test_mcp_child_session() {
  export MCP_SERVERS="test"
  source ~/.qwen/scripts/qwen-session-env.sh
  start_root_session
  
  if start_child_session "reviewer" "test" 2>/dev/null; then
    echo "FAIL: MCP 环境下子会话不应成功"
    return 1
  fi
}
```

---

## Phase 3：会话清理（2-3 天）⭐⭐⭐⭐

### 任务清单

| ID | 任务 | 优先级 | 预计工时 | 状态 |
|----|------|--------|----------|------|
| 3.1 | 导出功能 | P0 | 4 小时 | ⏳ |
| 3.2 | 清理功能 | P0 | 4 小时 | ⏳ |
| 3.3 | 价值评级系统 | P1 | 4 小时 | ⏳ |
| 3.4 | 清理测试 | P0 | 4 小时 | ⏳ |

---

### 任务 3.1：导出功能

**文件**: `~/.qwen/scripts/session_export.sh`

**验收标准**:
- [ ] 日志正确导出
- [ ] 文件名包含时间戳
- [ ] 支持自定义导出目录

**依赖**: 任务 1.2

**实施步骤**:
1. 创建脚本文件
2. 实现日志查找
3. 实现文件复制
4. 添加时间戳

---

### 任务 3.2：清理功能

**文件**: `~/.qwen/scripts/session_cleanup.sh`

**验收标准**:
- [ ] 正确识别子会话
- [ ] 根据评级决定是否清理
- [ ] 清理环境变量

**依赖**: 任务 3.1

**实施步骤**:
1. 创建脚本文件
2. 实现子会话查找
3. 实现条件清理
4. 实现环境变量清理

---

### 任务 3.3：价值评级系统

**文件**: `~/.qwen/scripts/value_rating.sh`

**验收标准**:
- [ ] 支持 high/medium/low 评级
- [ ] 评级影响清理决策
- [ ] 可自定义评级标准

**依赖**: 任务 3.2

**实施步骤**:
1. 创建脚本文件
2. 定义评级标准
3. 实现评级函数
4. 集成到清理流程

---

### 任务 3.4：清理测试

**文件**: `~/.qwen/scripts/test_cleanup.sh`

**验收标准**:
- [ ] 测试所有清理场景
- [ ] 验证导出功能
- [ ] 验证清理逻辑

**依赖**: 任务 3.1-3.3

---

## Phase 4：可观测性（3-5 天）⭐⭐⭐

### 任务清单

| ID | 任务 | 优先级 | 预计工时 | 状态 |
|----|------|--------|----------|------|
| 4.1 | 会话树可视化 | P1 | 8 小时 | ⏳ |
| 4.2 | Task 日志聚合 | P1 | 8 小时 | ⏳ |
| 4.3 | 监控指标收集 | P1 | 8 小时 | ⏳ |
| 4.4 | 告警规则配置 | P1 | 8 小时 | ⏳ |

---

### 任务 4.1：会话树可视化

**文件**: `~/.qwen/scripts/session_tree.sh`

**验收标准**:
- [ ] 正确显示会话层级
- [ ] 支持过滤和搜索
- [ ] 输出格式美观

**依赖**: 任务 1.2

**输出示例**:
```
会话树:
├─ abc123... (根)
│  └─ def456... (父：abc123)
│     └─ ghi789... (父：def456)
├─ jkl012... (根)
│  └─ mno345... (父：jkl012)
```

---

### 任务 4.2：Task 日志聚合

**文件**: `~/.qwen/scripts/task_log_aggregate.sh`

**验收标准**:
- [ ] 聚合所有 Task 调用
- [ ] 提取关键信息
- [ ] 支持 JSON 输出

**依赖**: 任务 1.2

---

### 任务 4.3：监控指标收集

**文件**: `~/.oml/core/session_metrics.py`

**验收标准**:
- [ ] 收集会话数量
- [ ] 收集 Token 使用
- [ ] 收集操作延迟

**依赖**: 任务 3.1

---

### 任务 4.4：告警规则配置

**文件**: `~/.oml/config/alerts.yaml`

**验收标准**:
- [ ] 定义告警条件
- [ ] 配置通知渠道
- [ ] 测试告警触发

**依赖**: 任务 4.3

---

## Phase 5：安全与性能（4-6 周）⭐⭐⭐⭐⭐

### 任务清单

| ID | 任务 | 优先级 | 预计工时 | 状态 |
|----|------|--------|----------|------|
| 5.1 | 会话加密 | P0 | 1 周 | ⏳ |
| 5.2 | 审计日志 | P0 | 1 周 | ⏳ |
| 5.3 | 并发执行 | P0 | 1 周 | ⏳ |
| 5.4 | 懒加载 | P0 | 1 周 | ⏳ |
| 5.5 | 重试机制 | P0 | 3 天 | ⏳ |
| 5.6 | 回滚机制 | P0 | 3 天 | ⏳ |
| 5.7 | 简化 CLI | P1 | 1 周 | ⏳ |
| 5.8 | TUI 界面 | P1 | 1 周 | ⏳ |

---

## 依赖关系图

```
Phase 1 (基础实现)
    │
    ├─ 1.1 会话 ID 编码
    ├─ 1.2 环境变量注入 ────┬──── 1.3 MCP 检测
    │                        │
    │                        └──── 1.4 基础测试
    │
    ▼
Phase 2 (递归预防)
    │
    ├─ 2.1 MCP 检测增强
    ├─ 2.2 递归检查 ────────┬──── 2.3 深度限制
    │                        │
    │                        └──── 2.4 集成测试
    │
    ▼
Phase 3 (会话清理)
    │
    ├─ 3.1 导出功能 ────────┬──── 3.2 清理功能
    │                        │
    │                        ├──── 3.3 价值评级
    │                        │
    │                        └──── 3.4 清理测试
    │
    ▼
Phase 4 (可观测性)
    │
    ├─ 4.1 会话树可视化
    ├─ 4.2 Task 日志聚合
    ├─ 4.3 监控指标
    │
    └──── 4.4 告警规则
    │
    ▼
Phase 5 (安全与性能)
    │
    ├─ 5.1 会话加密
    ├─ 5.2 审计日志
    ├─ 5.3 并发执行
    ├─ 5.4 懒加载
    ├─ 5.5 重试机制
    ├─ 5.6 回滚机制
    ├─ 5.7 简化 CLI
    │
    └──── 5.8 TUI 界面
```

---

## 总体验收标准

### 功能性

- [ ] 所有 Phase 1-3 任务完成
- [ ] 测试通过率 100%
- [ ] 文档完整

### 性能

- [ ] 会话 ID 生成 < 10ms
- [ ] 环境变量设置 < 50ms
- [ ] 递归检查 < 20ms

### 安全性

- [ ] 无敏感信息泄露
- [ ] 所有文件权限正确
- [ ] 审计日志完整

### 可用性

- [ ] CLI 命令简化 50%+
- [ ] 错误信息清晰
- [ ] 提供完整文档

---

## 风险与缓解

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|----------|
| 会话 ID 碰撞 | 低 | 高 | 使用 22 字符 Base64URL |
| 环境变量泄漏 | 中 | 中 | 会话结束清理 |
| MCP 检测遗漏 | 低 | 高 | 多重检测 |
| 清理脚本误删 | 中 | 高 | 先导出后删除 + 确认 |
| Qwen CLI API 变更 | 中 | 中 | 封装桥接层 |
| 递归预防绕过 | 低 | 高 | 入口/出口双重检查 |

---

## 🔗 相关文档

- [会话管理](./SESSION-MANAGEMENT.md) - 完整指南
- [上下文优化](./CONTEXT-OPTIMIZATION.md) - 三层架构
- [架构优化](./ARCHITECTURE-OPTIMIZATION.md) - 实施路线图
- [TypeScript 支持](./TYPESCRIPT-SUPPORT.md) - TS 实现

---

*最后更新：2026-03-22 | 维护者：Oh My LiteCode Team*
