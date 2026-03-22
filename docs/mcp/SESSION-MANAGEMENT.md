# MCP 会话管理指南 | Session Management Guide

> **版本**: 1.0.0 | **标签**: [QWEN-SPECIFIC] [SESSION]

---

## 📋 概述

本文档描述 Qwen Code 递归子代理的完整会话管理方案，包括会话生命周期、环境变量注入、递归预防和会话清理。

### 核心设计原则

1. **环境变量传递** - 使用 `QWEN_*` 前缀避免冲突
2. **64 位编码** - Base64URL 编码生成 22 字符会话 ID
3. **递归预防** - 多重检测阻止无限递归
4. **先导出后清理** - 确保数据不丢失

---

## 🏗️ 架构设计

### 会话状态机

```bash
# 根会话
QWEN_SESSION_ID=abc123...           # 22 字符 Base64URL
QWEN_PARENT_SESSION=                 # 空表示根会话
QWEN_SESSION_DEPTH=0                 # 深度追踪
QWEN_AGENT_NAME=                     # 代理名称
QWEN_TASK_NAME=                      # 任务名称

# 子会话
QWEN_SESSION_ID=def456...
QWEN_PARENT_SESSION=abc123...
QWEN_SESSION_DEPTH=1
QWEN_AGENT_NAME=reviewer
QWEN_TASK_NAME=auth-module
```

### 完整工作流

```
┌─────────────────────────────────────────────────────────────┐
│                    会话生命周期管理                          │
├─────────────────────────────────────────────────────────────┤
│  1. 启动根会话                                               │
│     $ source ~/.qwen/scripts/qwen-session-env.sh            │
│     $ start_root_session                                     │
│     → QWEN_SESSION_ID=1SCkGd8VSELbfsEBsKpFgg                │
│     → QWEN_PARENT_SESSION=                                   │
│     → QWEN_SESSION_DEPTH=0                                   │
│                                                              │
│  2. 启动子会话                                               │
│     $ start_child_session "reviewer" "auth-module"          │
│     → QWEN_SESSION_ID=abc123...                              │
│     → QWEN_PARENT_SESSION=1SCkGd8VSELbfsEBsKpFgg            │
│     → QWEN_SESSION_DEPTH=1                                   │
│                                                              │
│  3. MCP 调用检查                                             │
│     $ mcp_call_guard                                          │
│     → 检查 QWEN_PARENT_SESSION 是否为空                        │
│     → 非空则阻止调用                                          │
│                                                              │
│  4. 会话结束                                                 │
│     $ on_session_end "low"                                   │
│     → 导出日志到 qwenx-export/                               │
│     → 清理低价值子会话                                        │
│     → 清理环境变量                                            │
└─────────────────────────────────────────────────────────────┘
```

---

## 🔧 核心组件

### 1. 会话 ID 编码工具

**文件**: `~/.qwen/scripts/session_id_encode.sh`

```bash
#!/data/data/com.termux/files/usr/bin/bash
# 64 位编码生成 (22 字符 Base64URL)

set -euo pipefail

generate_session_id() {
    # 生成 16 字节随机数 → 24 字符 base64 → 截断 22 字符
    head -c 16 /dev/urandom | base64 | tr '+/' '_.' | tr -d '=' | cut -c1-22
}

# 支持命令行调用
if [ "${1:-}" = "--generate" ]; then
    generate_session_id
fi
```

**特点**:
- 使用 `/dev/urandom` 保证随机性
- Base64URL 编码 (`_` 替代 `+`, `.` 替代 `/`)
- 22 字符长度 (128 位熵)

---

### 2. 环境变量注入脚本

**文件**: `~/.qwen/scripts/qwen-session-env.sh`

```bash
#!/data/data/com.termux/files/usr/bin/bash
# 环境变量注入和会话管理

set -euo pipefail

# 配置
QWEN_SCRIPTS_DIR="${HOME}/.qwen/scripts"
QWEN_EXPORT_DIR="${HOME}/qwenx-export"

# 生成会话 ID
generate_session_id() {
    head -c 16 /dev/urandom | base64 | tr '+/' '_.' | tr -d '=' | cut -c1-22
}

# 启动根会话
start_root_session() {
    export QWEN_SESSION_ID="$(generate_session_id)"
    export QWEN_PARENT_SESSION=""
    export QWEN_SESSION_DEPTH=0
    
    echo "✅ 根会话启动：$QWEN_SESSION_ID"
}

# 启动子会话
start_child_session() {
    local agent_name="$1"
    local task_name="$2"
    local parent_id="$QWEN_SESSION_ID"
    
    # 检查递归
    if [[ -n "$QWEN_PARENT_SESSION" ]]; then
        echo "❌ 错误：禁止在子会话中创建子会话" >&2
        return 1
    fi
    
    export QWEN_SESSION_ID="$(generate_session_id)"
    export QWEN_PARENT_SESSION="$parent_id"
    export QWEN_SESSION_DEPTH=1
    export QWEN_AGENT_NAME="$agent_name"
    export QWEN_TASK_NAME="$task_name"
    
    echo "✅ 子会话启动：$QWEN_SESSION_ID (父：$parent_id)"
}

# 清理环境变量
cleanup_env() {
    unset QWEN_SESSION_ID
    unset QWEN_PARENT_SESSION
    unset QWEN_SESSION_DEPTH
    unset QWEN_AGENT_NAME
    unset QWEN_TASK_NAME
}

# 自动加载
if [ -z "$QWEN_SESSION_ID" ]; then
    start_root_session
fi
```

---

### 3. MCP 递归检测器

**文件**: `~/.qwen/scripts/mcp_session_guard.py`

```python
#!/usr/bin/env python3
# MCP 递归检测

import os
import sys
import json

def detect_mcp_context():
    """检测 MCP 环境"""
    # 检查环境变量
    if os.environ.get('MCP_SERVERS') or os.environ.get('OML_MCP_ENABLED'):
        return True
    
    # 检查配置文件
    config_path = os.path.expanduser('~/.qwen/settings.json')
    try:
        with open(config_path) as f:
            config = json.load(f)
        if 'mcpServers' in config.get('mcp', {}):
            return True
    except:
        pass
    
    return False

def check_recursion_safety():
    """检查递归安全性"""
    parent_session = os.environ.get('QWEN_PARENT_SESSION')
    session_depth = int(os.environ.get('QWEN_SESSION_DEPTH', 0))
    
    # 规则 1: 子会话中禁止创建子会话
    if parent_session:
        return False, "子会话禁止递归"
    
    # 规则 2: MCP 环境下禁止子会话
    if detect_mcp_context() and session_depth > 0:
        return False, "MCP 环境禁止子会话"
    
    # 规则 3: 深度限制
    if session_depth >= 3:
        return False, "达到最大深度 3"
    
    return True, "允许"

if __name__ == '__main__':
    allowed, reason = check_recursion_safety()
    print(json.dumps({'allowed': allowed, 'reason': reason}))
    sys.exit(0 if allowed else 1)
```

---

### 4. 会话清理脚本

**文件**: `~/.qwen/scripts/session_cleanup.sh`

```bash
#!/data/data/com.termux/files/usr/bin/bash
# 会话清理和导出

set -euo pipefail

QWEN_EXPORT_DIR="${HOME}/qwenx-export/sessions"

# 导出会话日志
export_session_logs() {
    local session_id="$1"
    local export_file="$QWEN_EXPORT_DIR/session-$session_id-$(date +%Y%m%d-%H%M%S).json"
    
    mkdir -p "$QWEN_EXPORT_DIR"
    
    # 查找并复制日志
    find ~/.qwen/tmp -name "logs.json" -path "*$session_id*" \
        -exec cp {} "$export_file" \; 2>/dev/null || true
    
    echo "📦 已导出：$export_file"
}

# 清理子会话
cleanup_child_sessions() {
    local parent_id="$1"
    local keep_logs="${2:-true}"
    
    echo "🔍 查找父会话 $parent_id 的子会话..."
    
    for chat_file in ~/.qwen/projects/*/chats/*.jsonl; do
        if grep -q "\"parentUuid\":\"$parent_id\"" "$chat_file" 2>/dev/null; then
            if [ "$keep_logs" = "false" ]; then
                rm -f "$chat_file"
                echo "  ❌ 清理：$chat_file"
            else
                echo "  ✅ 保留日志：$chat_file"
            fi
        fi
    done
}

# 会话结束处理
on_session_end() {
    local session_id="${QWEN_SESSION_ID:-}"
    local value_rating="${1:-low}"  # high/medium/low
    
    if [ -z "$session_id" ]; then
        echo "⚠️ 无活动会话"
        return 0
    fi
    
    echo "🔚 结束会话：$session_id (评级：$value_rating)"
    
    # 1. 导出日志
    export_session_logs "$session_id"
    
    # 2. 根据价值评级决定是否清理子会话
    if [ "$value_rating" = "low" ]; then
        cleanup_child_sessions "$session_id" "false"
    else
        cleanup_child_sessions "$session_id" "true"
    fi
    
    # 3. 清理环境变量
    cleanup_env
    
    echo "✅ 清理完成"
}

# 支持命令行调用
if [ "${1:-}" = "--cleanup" ]; then
    on_session_end "${2:-low}"
fi
```

---

## 📊 风险评估

| 风险 | 概率 | 影响 | 严重性 | 缓解措施 |
|------|------|------|--------|----------|
| Base64URL 终端不兼容 | 低 | 低 | 🟢 低 | 使用标准字符集测试 |
| 环境变量被覆盖 | 中 | 中 | 🟡 中 | 使用唯一前缀 `QWEN_` |
| 清理脚本误删 | 中 | 高 | 🟠 高 | 先导出后删除 + 确认 |
| MCP 检测遗漏 | 低 | 中 | 🟡 中 | 多重检测 (env+config) |
| 会话 ID 碰撞 | 低 | 高 | 🟠 高 | 使用 22 字符 Base64URL |

---

## ✅ Go/No-Go 决策

| 条件 | 状态 |
|------|------|
| 64 位编码 | ✅ Go |
| 会话名前缀 | ❌ No-Go (改用环境变量) |
| MCP 检测 | ✅ Go |
| 会话清理 | ✅ Go (需确认机制) |

---

## 🔗 相关文档

- [上下文优化](./CONTEXT-OPTIMIZATION.md) - 三层架构设计
- [架构优化](./ARCHITECTURE-OPTIMIZATION.md) - 实施路线图
- [实施清单](./IMPLEMENTATION-CHECKLIST.md) - 详细任务列表

---

*最后更新：2026-03-22 | 维护者：Oh My LiteCode Team*
