# OML 插件开发指南

**版本**: 0.2.0  
**日期**: 2026-03-23

---

## 📖 概述

OML 插件系统支持三种类型的插件：
- **MCP** (Model Context Protocol) - 模型上下文协议服务
- **Subagents** - 子代理
- **Skills** - 技能

---

## 🎯 插件结构

### 基本结构

```
plugins/
├── mcps/              # MCP 服务
│   └── <name>/
│       ├── plugin.json
│       ├── main.sh
│       ├── scripts/
│       └── tests/
├── subagents/         # 子代理
│   └── <name>/
│       ├── plugin.json
│       ├── main.sh
│       ├── scripts/
│       └── tests/
└── skills/            # 技能
    └── <name>/
        ├── plugin.json
        ├── main.sh
        ├── scripts/
        └── tests/
```

---

## 📝 plugin.json

### 基本格式

```json
{
  "name": "plugin-name",
  "version": "0.2.0",
  "type": "mcp|subagent|skill",
  "description": "插件描述",
  "author": "作者名",
  "license": "MIT",
  "platforms": ["termux", "gnu-linux"],
  "dependencies": ["bash", "python3"],
  "commands": [
    {
      "name": "command-name",
      "description": "命令描述",
      "handler": "main.sh command_name"
    }
  ]
}
```

### 字段说明

| 字段 | 必填 | 说明 |
|------|------|------|
| `name` | ✅ | 插件名称（小写，连字符分隔） |
| `version` | ✅ | 版本号（必须与 OML 版本一致） |
| `type` | ✅ | 插件类型（mcp/subagent/skill） |
| `description` | ✅ | 插件描述 |
| `author` | ✅ | 作者名 |
| `license` | ✅ | 许可证（推荐 MIT） |
| `platforms` | ✅ | 支持的平台 |
| `dependencies` | ✅ | 依赖项列表 |
| `commands` | ✅ | 命令列表 |

---

## 🔧 main.sh

### 基本模板

```bash
#!/usr/bin/env bash
# Plugin Name - Description
#
# Usage:
#   oml <type> <name> <command>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# Command implementations
cmd_example() {
    echo -e "${BLUE}Executing example command...${NC}"
    # Your implementation here
    echo -e "${GREEN}✓ Complete${NC}"
}

# Help message
show_help() {
    cat <<EOF
Plugin Name - Description

Usage: oml <type> name <command>

Commands:
  example    Example command
  help       Show this help

EOF
}

# Main function
main() {
    local cmd="${1:-help}"; shift || true
    
    case "$cmd" in
        example) cmd_example ;;
        help|--help|-h) show_help ;;
        *) echo -e "${RED}Unknown command: $cmd${NC}"; show_help; exit 1 ;;
    esac
}

main "$@"
```

---

## 🧪 测试

### 测试模板

```bash
#!/usr/bin/env bash
# Test suite for plugin-name

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
MAIN_SH="${PLUGIN_DIR}/main.sh"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'

# Test counters
TESTS_PASSED=0; TESTS_FAILED=0; TESTS_TOTAL=0

# Test helper
run_test() {
    local test_name="$1"
    local test_cmd="$2"
    local expected_exit="${3:-0}"
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    echo -n "Testing: ${test_name} ... "
    
    set +e
    output=$(eval "$test_cmd" 2>&1)
    actual_exit=$?
    set -e
    
    if [[ "$actual_exit" -eq "$expected_exit" ]]; then
        echo -e "${GREEN}✓ PASSED${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗ FAILED${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Run tests
echo "Running tests..."
run_test "Help command" "$MAIN_SH help" 0
run_test "Unknown command" "$MAIN_SH unknown" 1

# Summary
echo ""
echo "Tests: $TESTS_PASSED/$TESTS_TOTAL passed"
[[ $TESTS_FAILED -eq 0 ]] && exit 0 || exit 1
```

---

## 📋 开发流程

### 1. 创建插件目录

```bash
mkdir -p plugins/mcps/my-plugin/{scripts,tests}
```

### 2. 创建 plugin.json

```bash
cat > plugins/mcps/my-plugin/plugin.json <<EOF
{
  "name": "my-plugin",
  "version": "0.2.0",
  "type": "mcp",
  "description": "My custom plugin",
  "author": "Your Name",
  "license": "MIT",
  "platforms": ["termux", "gnu-linux"],
  "dependencies": ["bash"],
  "commands": [
    {"name": "hello", "description": "Say hello", "handler": "main.sh hello"}
  ]
}
EOF
```

### 3. 创建 main.sh

```bash
cat > plugins/mcps/my-plugin/main.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'

cmd_hello() { echo -e "${GREEN}Hello from my-plugin!${NC}"; }
show_help() { echo "Usage: oml mcp my-plugin <command>"; echo "Commands: hello, help"; }

main() {
    local cmd="${1:-help}"; shift || true
    case "$cmd" in
        hello) cmd_hello ;; help|--help|-h) show_help ;;
        *) echo "Unknown: $cmd"; exit 1 ;;
    esac
}
main "$@"
EOF
chmod +x plugins/mcps/my-plugin/main.sh
```

### 4. 创建测试

```bash
cat > plugins/mcps/my-plugin/tests/test-plugin.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
MAIN_SH="$(dirname "$0")/../main.sh"
echo "Testing help..."
$MAIN_SH help >/dev/null && echo "✓ Help works" || echo "✗ Help failed"
echo "Testing hello..."
$MAIN_SH hello >/dev/null && echo "✓ Hello works" || echo "✗ Hello failed"
EOF
chmod +x plugins/mcps/my-plugin/tests/test-plugin.sh
```

### 5. 运行测试

```bash
bash plugins/mcps/my-plugin/tests/test-plugin.sh
```

### 6. 提交插件

```bash
git add plugins/mcps/my-plugin/
git commit -m "feat: Add my-plugin MCP"
git push origin main
```

---

## ✅ 验收标准

### 代码质量

- [ ] 使用 `set -euo pipefail`
- [ ] 所有变量加引号
- [ ] 函数命名规范 (`cmd_*`, `show_*`)
- [ ] 完整的错误处理
- [ ] 颜色输出

### 文档

- [ ] plugin.json 完整
- [ ] main.sh 有注释
- [ ] help 信息清晰
- [ ] 测试用例完整

### 测试

- [ ] 单元测试通过
- [ ] 集成测试通过
- [ ] 边界条件测试
- [ ] 错误处理测试

---

## 🔗 相关文档

- [API 参考](../api/API-REFERENCE.md)
- [MCP 开发指南](MCP-DEV-GUIDE.md)
- [最佳实践](BEST-PRACTICES.md)

---

**维护者**: OML Team  
**版本**: 0.2.0
