#!/usr/bin/env bash
# Grep-App MCP Plugin - Test Suite
# Tests all commands and MCP tools
#
# Usage:
#   ./test-grep-app.sh              # Run all tests
#   ./test-grep-app.sh search       # Run specific test
#   ./test-grep-app.sh --verbose    # Verbose output

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$SCRIPT_DIR"
MAIN_SH="${PLUGIN_DIR}/main.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Verbose mode
VERBOSE=false

# ============================================================================
# Utility Functions
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $*"
    ((TESTS_PASSED++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $*"
    ((TESTS_FAILED++))
}

log_skip() {
    echo -e "${YELLOW}[SKIP]${NC} $*"
    ((TESTS_SKIPPED++))
}

log_test() {
    echo -e "${BLUE}[TEST]${NC} $*"
}

# Check if running on Termux
is_termux() {
    [[ -d "/data/data/com.termux/files/usr" ]]
}

# Create test directory with sample files
setup_test_env() {
    local test_dir
    test_dir=$(mktemp -d)
    echo "$test_dir"

    # Create sample files
    mkdir -p "${test_dir}/src"
    mkdir -p "${test_dir}/tests"
    mkdir -p "${test_dir}/node_modules"  # Should be excluded

    # Python file
    cat > "${test_dir}/src/main.py" <<'EOF'
#!/usr/bin/env python3
"""Main module for testing."""

import os
import sys

# TODO: Add more features
def hello_world():
    """Print hello world."""
    print("Hello, World!")

class Greeter:
    """A simple greeter class."""

    def __init__(self, name):
        self.name = name

    def greet(self):
        return f"Hello, {self.name}!"

if __name__ == "__main__":
    hello_world()
EOF

    # JavaScript file
    cat > "${test_dir}/src/app.js" <<'EOF'
// Main application module
// TODO: Implement error handling

const express = require('express');

function createApp() {
    const app = express();

    app.get('/', (req, res) => {
        res.send('Hello, World!');
    });

    return app;
}

class Server {
    constructor(port) {
        this.port = port;
    }

    start() {
        console.log(`Server starting on port ${this.port}`);
    }
}

module.exports = { createApp, Server };
EOF

    # TypeScript file
    cat > "${test_dir}/src/utils.ts" <<'EOF'
// Utility functions
// FIXME: Handle edge cases

export interface Config {
    name: string;
    port: number;
}

export function loadConfig(path: string): Config {
    // TODO: Implement config loading
    return { name: 'app', port: 8080 };
}

export class Logger {
    private prefix: string;

    constructor(prefix: string) {
        this.prefix = prefix;
    }

    log(message: string): void {
        console.log(`[${this.prefix}] ${message}`);
    }
}
EOF

    # Test file
    cat > "${test_dir}/tests/test_main.py" <<'EOF'
import unittest

class TestMain(unittest.TestCase):
    def test_hello(self):
        self.assertEqual(1, 1)

    def test_greeter(self):
        # TODO: Add more tests
        pass

if __name__ == '__main__':
    unittest.main()
EOF

    # File in node_modules (should be excluded)
    cat > "${test_dir}/node_modules/fake.js" <<'EOF'
// This should not be found
console.log("EXCLUDED");
EOF

    echo "$test_dir"
}

# Cleanup test directory
cleanup_test_env() {
    local test_dir="$1"
    if [[ -d "$test_dir" ]]; then
        rm -rf "$test_dir"
    fi
}

# Assert command succeeds
assert_success() {
    local cmd="$1"
    local description="${2:-Command}"

    log_test "$description"

    if eval "$cmd" >/dev/null 2>&1; then
        log_success "$description"
        return 0
    else
        log_fail "$description (command failed)"
        return 1
    fi
}

# Assert command output contains pattern
assert_contains() {
    local cmd="$1"
    local pattern="$2"
    local description="${3:-Output contains pattern}"

    log_test "$description"

    local output
    output=$(eval "$cmd" 2>&1)

    if echo "$output" | grep -q "$pattern"; then
        log_success "$description"
        return 0
    else
        log_fail "$description (pattern '$pattern' not found)"
        if [[ "$VERBOSE" == "true" ]]; then
            echo "  Output: $output"
        fi
        return 1
    fi
}

# Assert command output is valid JSON
assert_json() {
    local cmd="$1"
    local description="${2:-Output is valid JSON}"

    log_test "$description"

    local output
    output=$(eval "$cmd" 2>&1)

    if echo "$output" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
        log_success "$description"
        return 0
    else
        log_fail "$description (invalid JSON)"
        if [[ "$VERBOSE" == "true" ]]; then
            echo "  Output: $output"
        fi
        return 1
    fi
}

# ============================================================================
# Test Cases
# ============================================================================

test_help() {
    echo ""
    echo "=== Testing Help Command ==="

    assert_success "$MAIN_SH help" "Help command runs"
    assert_contains "$MAIN_SH help" "Usage:" "Help shows usage"
    assert_contains "$MAIN_SH help" "search" "Help mentions search command"
    assert_contains "$MAIN_SH help" "regex" "Help mentions regex command"
    assert_contains "$MAIN_SH help" "count" "Help mentions count command"
    assert_contains "$MAIN_SH help" "files" "Help mentions files command"
    assert_contains "$MAIN_SH help" "config" "Help mentions config command"
}

test_search() {
    echo ""
    echo "=== Testing Search Command ==="

    local test_dir
    test_dir=$(setup_test_env)

    # Test basic search
    assert_contains "$MAIN_SH search function -p $test_dir --ext py" "def " "Search finds Python functions"
    assert_contains "$MAIN_SH search function -p $test_dir --ext js" "function" "Search finds JavaScript functions"

    # Test search with JSON output
    assert_json "$MAIN_SH search function -p $test_dir --ext py --json" "Search returns valid JSON"

    # Test search for TODO comments
    assert_contains "$MAIN_SH search "TODO comments" -p $test_dir" "TODO" "Search finds TODO comments"

    # Test search for class
    assert_contains "$MAIN_SH search "class definition" -p $test_dir --ext py" "class " "Search finds class definitions"

    # Test search excludes node_modules
    local result
    result=$($MAIN_SH search "EXCLUDED" -p "$test_dir" 2>&1)
    if ! echo "$result" | grep -q "node_modules"; then
        log_success "Search excludes node_modules"
        ((TESTS_PASSED++))
    else
        log_fail "Search should exclude node_modules"
        ((TESTS_FAILED++))
    fi

    cleanup_test_env "$test_dir"
}

test_regex() {
    echo ""
    echo "=== Testing Regex Command ==="

    local test_dir
    test_dir=$(setup_test_env)

    # Test basic regex
    assert_contains "$MAIN_SH regex "def \w+\(" -p $test_dir --ext py" "def " "Regex finds Python function definitions"
    assert_contains "$MAIN_SH regex "function \w+\(" -p $test_dir --ext js" "function " "Regex finds JS function definitions"

    # Test regex with JSON output
    assert_json "$MAIN_SH regex "def \w+\(" -p $test_dir --ext py --json" "Regex returns valid JSON"

    # Test case insensitive
    assert_contains "$MAIN_SH regex "TODO" -p $test_dir -i" "TODO" "Regex case insensitive search"

    # Test class pattern
    assert_contains "$MAIN_SH regex "class \w+" -p $test_dir --ext py" "class " "Regex finds class definitions"

    cleanup_test_env "$test_dir"
}

test_count() {
    echo ""
    echo "=== Testing Count Command ==="

    local test_dir
    test_dir=$(setup_test_env)

    # Test basic count
    assert_contains "$MAIN_SH count "TODO" -p $test_dir" "Total matches:" "Count shows total"
    assert_contains "$MAIN_SH count "TODO" -p $test_dir" "Files with matches:" "Count shows file count"

    # Test count with JSON output
    assert_json "$MAIN_SH count "TODO" -p $test_dir --json" "Count returns valid JSON"

    # Test count for function definitions
    local result
    result=$($MAIN_SH count "def \|function " -p "$test_dir" --ext py,js 2>&1)
    if echo "$result" | grep -q "Total matches:"; then
        log_success "Count finds multiple patterns"
        ((TESTS_PASSED++))
    else
        log_fail "Count should find multiple patterns"
        ((TESTS_FAILED++))
    fi

    cleanup_test_env "$test_dir"
}

test_files() {
    echo ""
    echo "=== Testing Files Command ==="

    local test_dir
    test_dir=$(setup_test_env)

    # Test basic files
    assert_contains "$MAIN_SH files "TODO" -p $test_dir" ".py" "Files finds Python files"
    assert_contains "$MAIN_SH files "TODO" -p $test_dir" ".js" "Files finds JavaScript files"

    # Test files with JSON output
    assert_json "$MAIN_SH files "TODO" -p $test_dir --json" "Files returns valid JSON"

    # Test files with extension filter
    local result
    result=$($MAIN_SH files "def " -p "$test_dir" --ext py 2>&1)
    if echo "$result" | grep -q "\.py"; then
        log_success "Files respects extension filter"
        ((TESTS_PASSED++))
    else
        log_fail "Files should respect extension filter"
        ((TESTS_FAILED++))
    fi

    cleanup_test_env "$test_dir"
}

test_config() {
    echo ""
    echo "=== Testing Config Command ==="

    # Test show config
    assert_success "$MAIN_SH config" "Config show runs"

    # Test config keys mentioned
    assert_contains "$MAIN_SH config" "default_path\|max_results\|exclude_dirs" "Config shows available keys"
}

test_status() {
    echo ""
    echo "=== Testing Status Command ==="

    # Test status command
    assert_success "$MAIN_SH status" "Status command runs"
    assert_contains "$MAIN_SH status" "Grep-App MCP Status" "Status shows header"
    assert_contains "$MAIN_SH status" "Platform:" "Status shows platform"
    assert_contains "$MAIN_SH status" "Dependencies:" "Status shows dependencies"
}

test_mcp_stdio() {
    echo ""
    echo "=== Testing MCP stdio Mode ==="

    # Test initialize request
    local init_request='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
    assert_json "echo '$init_request' | $MAIN_SH mcp-stdio 2>/dev/null" "MCP initialize returns JSON"

    # Test tools/list request
    local tools_request='{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
    local tools_output
    tools_output=$(echo "$tools_request" | $MAIN_SH mcp-stdio 2>/dev/null || true)

    if echo "$tools_output" | grep -q "grep_search_intent"; then
        log_success "MCP tools/list includes grep_search_intent"
        ((TESTS_PASSED++))
    else
        log_fail "MCP tools/list should include grep_search_intent"
        ((TESTS_FAILED++))
    fi

    if echo "$tools_output" | grep -q "grep_regex"; then
        log_success "MCP tools/list includes grep_regex"
        ((TESTS_PASSED++))
    else
        log_fail "MCP tools/list should include grep_regex"
        ((TESTS_FAILED++))
    fi

    if echo "$tools_output" | grep -q "grep_count"; then
        log_success "MCP tools/list includes grep_count"
        ((TESTS_PASSED++))
    else
        log_fail "MCP tools/list should include grep_count"
        ((TESTS_FAILED++))
    fi

    if echo "$tools_output" | grep -q "grep_files_with_matches"; then
        log_success "MCP tools/list includes grep_files_with_matches"
        ((TESTS_PASSED++))
    else
        log_fail "MCP tools/list should include grep_files_with_matches"
        ((TESTS_FAILED++))
    fi

    if echo "$tools_output" | grep -q "grep_advanced"; then
        log_success "MCP tools/list includes grep_advanced"
        ((TESTS_PASSED++))
    else
        log_fail "MCP tools/list should include grep_advanced"
        ((TESTS_FAILED++))
    fi
}

test_dependencies() {
    echo ""
    echo "=== Testing Dependencies ==="

    # Check grep
    if command -v grep >/dev/null 2>&1; then
        log_success "grep is available"
    else
        log_fail "grep is not available"
    fi

    # Check find
    if command -v find >/dev/null 2>&1; then
        log_success "find is available"
    else
        log_fail "find is not available"
    fi

    # Check python3
    if command -v python3 >/dev/null 2>&1; then
        log_success "python3 is available"
    else
        log_fail "python3 is not available"
    fi
}

# ============================================================================
# Main Entry Point
# ============================================================================

run_all_tests() {
    test_dependencies
    test_help
    test_search
    test_regex
    test_count
    test_files
    test_config
    test_status
    test_mcp_stdio
}

show_summary() {
    echo ""
    echo "=============================================="
    echo "  Test Summary"
    echo "=============================================="
    echo ""
    echo -e "  ${GREEN}Passed:${NC}  $TESTS_PASSED"
    echo -e "  ${RED}Failed:${NC}  $TESTS_FAILED"
    echo -e "  ${YELLOW}Skipped:${NC} $TESTS_SKIPPED"
    echo ""

    local total=$((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))
    echo "  Total:   $total"
    echo ""

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}Some tests failed!${NC}"
        return 1
    fi
}

main() {
    echo ""
    echo "=============================================="
    echo "  Grep-App MCP Plugin - Test Suite"
    echo "=============================================="
    echo ""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            help|--help|-h)
                echo "Usage: $0 [options] [test_name]"
                echo ""
                echo "Options:"
                echo "  --verbose, -v    Verbose output"
                echo "  --help, -h       Show this help"
                echo ""
                echo "Test names:"
                echo "  help             Test help command"
                echo "  search           Test search command"
                echo "  regex            Test regex command"
                echo "  count            Test count command"
                echo "  files            Test files command"
                echo "  config           Test config command"
                echo "  status           Test status command"
                echo "  mcp_stdio        Test MCP stdio mode"
                echo "  dependencies     Test dependencies"
                echo ""
                echo "Examples:"
                echo "  $0               Run all tests"
                echo "  $0 search        Run search tests only"
                echo "  $0 -v            Run all tests with verbose output"
                exit 0
                ;;
            *)
                # Run specific test
                local test_name="test_$1"
                if declare -f "$test_name" >/dev/null 2>&1; then
                    $test_name
                else
                    log_fail "Unknown test: $1"
                fi
                shift
                ;;
        esac
    done

    # If no specific test was requested, run all
    if [[ $TESTS_PASSED -eq 0 && $TESTS_FAILED -eq 0 && $TESTS_SKIPPED -eq 0 ]]; then
        run_all_tests
    fi

    show_summary
}

main "$@"
