# OML MCP 开发指南

**版本**: 0.2.0  
**日期**: 2026-03-23

---

## 📖 概述

MCP (Model Context Protocol) 是 OML 的模型上下文协议服务。

---

## 🎯 MCP 结构

### 目录结构

```
plugins/mcps/<name>/
├── plugin.json          # 插件配置
├── main.sh              # 主入口
├── scripts/             # 辅助脚本
└── tests/               # 测试用例
```

---

## 📝 plugin.json

### 完整示例

```json
{
  "name": "my-mcp",
  "version": "0.2.0",
  "type": "mcp",
  "description": "My custom MCP service",
  "author": "Your Name",
  "license": "MIT",
  "platforms": ["termux", "gnu-linux"],
  "dependencies": ["bash", "python3"],
  "commands": [
    {
      "name": "query",
      "description": "Query data",
      "handler": "main.sh query"
    },
    {
      "name": "search",
      "description": "Search data",
      "handler": "main.sh search"
    }
  ],
  "security": {
    "requireConfirm": ["query"],
    "blockedOperations": ["DROP", "DELETE"]
  }
}
```

---

## 🔧 main.sh 开发

### 基本模板

```bash
#!/usr/bin/env bash
# My MCP - Description
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# Command implementations
cmd_query() {
    local param="${1:-}"
    echo -e "${BLUE}Querying...${NC}"
    # Implementation here
    echo -e "${GREEN}✓ Complete${NC}"
}

cmd_search() {
    local param="${1:-}"
    echo -e "${BLUE}Searching...${NC}"
    # Implementation here
    echo -e "${GREEN}✓ Complete${NC}"
}

# Help message
show_help() {
    cat <<EOF
My MCP - Description

Usage: oml mcp my-mcp <command>

Commands:
  query      Query data
  search     Search data
  help       Show this help

EOF
}

# Main function
main() {
    local cmd="${1:-help}"; shift || true
    case "$cmd" in
        query) cmd_query "$@" ;;
        search) cmd_search "$@" ;;
        help|--help|-h) show_help ;;
        *) echo -e "${RED}Unknown: $cmd${NC}"; exit 1 ;;
    esac
}

main "$@"
```

---

## 🧪 测试开发

### 测试模板

```bash
#!/usr/bin/env bash
# Test suite for my-mcp
set -euo pipefail

MAIN_SH="$(dirname "$0")/../main.sh"

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'

TESTS_PASSED=0; TESTS_FAILED=0

run_test() {
    local name="$1" cmd="$2" expected="${3:-0}"
    echo -n "Testing: $name ... "
    set +e
    $cmd >/dev/null 2>&1
    local actual=$?
    set -e
    if [[ $actual -eq $expected ]]; then
        echo -e "${GREEN}✓${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

echo "Running tests..."
run_test "Help command" "$MAIN_SH help" 0
run_test "Query command" "$MAIN_SH query" 1  # Expects param error

echo ""
echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
[[ $TESTS_FAILED -eq 0 ]] && exit 0 || exit 1
```

---

## 📋 开发检查清单

### 代码质量

- [ ] 使用 `set -euo pipefail`
- [ ] 所有变量加引号
- [ ] 函数命名规范 (`cmd_*`)
- [ ] 完整的错误处理
- [ ] 颜色输出

### 安全性

- [ ] 输入验证
- [ ] 路径安全检查
- [ ] 敏感操作确认
- [ ] 权限控制

### 文档

- [ ] plugin.json 完整
- [ ] main.sh 有注释
- [ ] help 信息清晰
- [ ] 测试用例完整

---

## 🔗 相关文档

- [API 参考](../api/API-REFERENCE.md)
- [插件开发指南](PLUGIN-DEV-GUIDE.md)
- [最佳实践](BEST-PRACTICES.md)

---

**维护者**: OML Team  
**版本**: 0.2.0
