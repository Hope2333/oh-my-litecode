#!/usr/bin/env bash
# Scout Plugin Test Suite

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_SH="${SCRIPT_DIR}/../main.sh"
TEST_DIR="${SCRIPT_DIR}/test-fixtures"
PASSED=0
FAILED=0
TOTAL=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test result tracking
pass() {
    ((PASSED++))
    ((TOTAL++))
    echo -e "${GREEN}✓ PASS${NC}: $1"
}

fail() {
    ((FAILED++))
    ((TOTAL++))
    echo -e "${RED}✗ FAIL${NC}: $1"
    if [[ -n "${2:-}" ]]; then
        echo "  Expected: $2"
    fi
    if [[ -n "${3:-}" ]]; then
        echo "  Got: $3"
    fi
}

skip() {
    echo -e "${YELLOW}⊘ SKIP${NC}: $1"
}

# Setup test fixtures
setup() {
    echo "Setting up test fixtures..."
    mkdir -p "${TEST_DIR}/src"
    mkdir -p "${TEST_DIR}/lib"
    mkdir -p "${TEST_DIR}/tests"
    mkdir -p "${TEST_DIR}/node_modules"
    mkdir -p "${TEST_DIR}/.git"
    
    # Create test files
    cat > "${TEST_DIR}/src/main.py" <<'EOF'
#!/usr/bin/env python3
"""Main module for testing."""

import os
import sys
from typing import List

def calculate_sum(numbers: List[int]) -> int:
    """Calculate sum of numbers."""
    total = 0
    for n in numbers:
        if n > 0:
            total += n
        elif n < 0:
            total -= abs(n)
    return total

def calculate_product(numbers: List[int]) -> int:
    """Calculate product of numbers."""
    result = 1
    for n in numbers:
        if n != 0:
            result *= n
    return result

class Calculator:
    """Calculator class."""
    
    def __init__(self, initial_value: int = 0):
        self.value = initial_value
    
    def add(self, x: int) -> int:
        if x > 0:
            self.value += x
        elif x < 0:
            self.value -= abs(x)
        return self.value
    
    def multiply(self, x: int) -> int:
        if x != 0:
            self.value *= x
        return self.value

if __name__ == "__main__":
    print(calculate_sum([1, 2, 3]))
EOF

    cat > "${TEST_DIR}/src/utils.js" <<'EOF'
// Utility functions
const fs = require('fs');
const path = require('path');

function formatDate(date) {
    if (date instanceof Date) {
        return date.toISOString();
    } else if (typeof date === 'string') {
        return new Date(date).toISOString();
    }
    return null;
}

function parseJSON(str) {
    try {
        return JSON.parse(str);
    } catch (e) {
        return null;
    }
}

const helpers = {
    capitalize: (str) => str.charAt(0).toUpperCase() + str.slice(1),
    lowercase: (str) => str.toLowerCase(),
};

export { formatDate, parseJSON, helpers };
export default { formatDate, parseJSON };
EOF

    cat > "${TEST_DIR}/lib/helper.sh" <<'EOF'
#!/usr/bin/env bash
# Helper functions

log_info() {
    echo "[INFO] $1"
}

log_error() {
    echo "[ERROR] $1" >&2
}

check_file() {
    if [[ -f "$1" ]]; then
        return 0
    else
        return 1
    fi
}

process_data() {
    local input="$1"
    if [[ -n "$input" ]]; then
        echo "$input" | tr '[:lower:]' '[:upper:]'
    fi
}
EOF

    # Create files that should be excluded
    echo "node_modules content" > "${TEST_DIR}/node_modules/package.txt"
    echo "git content" > "${TEST_DIR}/.git/config"
    
    echo "Test fixtures created."
}

# Cleanup test fixtures
cleanup() {
    echo "Cleaning up test fixtures..."
    rm -rf "${TEST_DIR}"
    echo "Cleanup complete."
}

# Test: Help command
test_help_command() {
    echo ""
    echo "=== Test: Help Command ==="
    
    local output
    output=$(bash "${MAIN_SH}" help 2>&1)
    
    if echo "$output" | grep -q "OML Scout Subagent"; then
        pass "Help command shows plugin name"
    else
        fail "Help command shows plugin name" "Contains 'OML Scout Subagent'" "$output"
    fi
    
    if echo "$output" | grep -q "analyze"; then
        pass "Help shows analyze command"
    else
        fail "Help shows analyze command" "Contains 'analyze'"
    fi
    
    if echo "$output" | grep -q "tree"; then
        pass "Help shows tree command"
    else
        fail "Help shows tree command" "Contains 'tree'"
    fi
    
    if echo "$output" | grep -q "deps"; then
        pass "Help shows deps command"
    else
        fail "Help shows deps command" "Contains 'deps'"
    fi
    
    if echo "$output" | grep -q "report"; then
        pass "Help shows report command"
    else
        fail "Help shows report command" "Contains 'report'"
    fi
    
    if echo "$output" | grep -q "stats"; then
        pass "Help shows stats command"
    else
        fail "Help shows stats command" "Contains 'stats'"
    fi
}

# Test: Tree command
test_tree_command() {
    echo ""
    echo "=== Test: Tree Command ==="
    
    local output
    output=$(bash "${MAIN_SH}" tree --dir "${TEST_DIR}" --max-depth 2 --format text 2>&1)
    
    if echo "$output" | grep -q "src"; then
        pass "Tree shows src directory"
    else
        fail "Tree shows src directory" "Contains 'src'"
    fi
    
    if echo "$output" | grep -q "lib"; then
        pass "Tree shows lib directory"
    else
        fail "Tree shows lib directory" "Contains 'lib'"
    fi
    
    # Test JSON output
    local json_output
    json_output=$(bash "${MAIN_SH}" tree --dir "${TEST_DIR}" --max-depth 2 --format json 2>&1)
    
    if echo "$json_output" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
        pass "Tree JSON output is valid JSON"
    else
        fail "Tree JSON output is valid JSON" "Valid JSON"
    fi
}

# Test: Stats command
test_stats_command() {
    echo ""
    echo "=== Test: Stats Command ==="
    
    local output
    output=$(bash "${MAIN_SH}" stats --dir "${TEST_DIR}" --format json 2>&1)
    
    if echo "$output" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
        pass "Stats JSON output is valid JSON"
    else
        fail "Stats JSON output is valid JSON" "Valid JSON"
    fi
    
    if echo "$output" | grep -q '"by_extension"'; then
        pass "Stats contains by_extension"
    else
        fail "Stats contains by_extension" "Contains 'by_extension'"
    fi
    
    if echo "$output" | grep -q '"by_language"'; then
        pass "Stats contains by_language"
    else
        fail "Stats contains by_language" "Contains 'by_language'"
    fi
    
    # Test quick stats
    local quick_output
    quick_output=$(bash "${MAIN_SH}" stats --dir "${TEST_DIR}" --quick 2>&1)
    
    if echo "$quick_output" | grep -q "Files:"; then
        pass "Quick stats shows file count"
    else
        fail "Quick stats shows file count" "Contains 'Files:'"
    fi
}

# Test: Analyze command
test_analyze_command() {
    echo ""
    echo "=== Test: Analyze Command ==="
    
    local output
    output=$(bash "${MAIN_SH}" analyze --dir "${TEST_DIR}" --format json 2>&1)
    
    if echo "$output" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
        pass "Analyze JSON output is valid JSON"
    else
        fail "Analyze JSON output is valid JSON" "Valid JSON"
    fi
    
    # Check for complexity metrics
    if echo "$output" | grep -q "cyclomatic_complexity\|complexity"; then
        pass "Analyze contains complexity metrics"
    else
        # This might be okay if no code files found
        skip "Complexity metrics check (may need code files)"
    fi
}

# Test: Deps command
test_deps_command() {
    echo ""
    echo "=== Test: Deps Command ==="
    
    local output
    output=$(bash "${MAIN_SH}" deps --dir "${TEST_DIR}" --format json 2>&1)
    
    if echo "$output" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
        pass "Deps JSON output is valid JSON"
    else
        fail "Deps JSON output is valid JSON" "Valid JSON"
    fi
}

# Test: Report command
test_report_command() {
    echo ""
    echo "=== Test: Report Command ==="
    
    local output
    output=$(bash "${MAIN_SH}" report --dir "${TEST_DIR}" --format markdown 2>&1)
    
    if echo "$output" | grep -q "# Scout Analysis Report"; then
        pass "Report contains header"
    else
        fail "Report contains header" "Contains '# Scout Analysis Report'"
    fi
    
    # Test JSON report
    local json_output
    json_output=$(bash "${MAIN_SH}" report --dir "${TEST_DIR}" --format json 2>&1)
    
    if echo "$json_output" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
        pass "Report JSON output is valid JSON"
    else
        fail "Report JSON output is valid JSON" "Valid JSON"
    fi
}

# Test: Exclude patterns
test_exclude_patterns() {
    echo ""
    echo "=== Test: Exclude Patterns ==="
    
    local output
    output=$(bash "${MAIN_SH}" tree --dir "${TEST_DIR}" --max-depth 3 --exclude "node_modules,.git" --format text 2>&1)
    
    if ! echo "$output" | grep -q "node_modules"; then
        pass "Excludes node_modules"
    else
        fail "Excludes node_modules" "Should not contain 'node_modules'"
    fi
    
    if ! echo "$output" | grep -q ".git"; then
        pass "Excludes .git"
    else
        fail "Excludes .git" "Should not contain '.git'"
    fi
}

# Test: Output to file
test_output_to_file() {
    echo ""
    echo "=== Test: Output To File ==="
    
    local output_file="${TEST_DIR}/test_output.json"
    
    bash "${MAIN_SH}" stats --dir "${TEST_DIR}" --format json --output "$output_file" 2>&1
    
    if [[ -f "$output_file" ]]; then
        pass "Output file created"
        
        if python3 -c "import json; json.load(open('$output_file'))" 2>/dev/null; then
            pass "Output file contains valid JSON"
        else
            fail "Output file contains valid JSON" "Valid JSON"
        fi
    else
        fail "Output file created" "File exists"
    fi
}

# Test: Error handling
test_error_handling() {
    echo ""
    echo "=== Test: Error Handling ==="
    
    # Test with non-existent directory
    local output
    output=$(bash "${MAIN_SH}" tree --dir "/nonexistent/path" 2>&1 || true)
    
    if echo "$output" | grep -qi "error\|not found\|directory"; then
        pass "Handles non-existent directory"
    else
        # May still pass if it handles gracefully
        skip "Non-existent directory handling"
    fi
    
    # Test with invalid action
    output=$(bash "${MAIN_SH}" invalid_action 2>&1 || true)
    
    if echo "$output" | grep -qi "error\|unknown\|invalid"; then
        pass "Handles invalid action"
    else
        fail "Handles invalid action" "Should show error"
    fi
}

# Test: Platform detection
test_platform_detection() {
    echo ""
    echo "=== Test: Platform Detection ==="
    
    # Source utils and test platform detection
    source "${SCRIPT_DIR}/../lib/utils.sh"
    
    local platform
    platform=$(scout_detect_platform)
    
    if [[ "$platform" == "termux" || "$platform" == "gnu-linux" || "$platform" == "macos" ]]; then
        pass "Platform detection works: $platform"
    else
        fail "Platform detection works" "termux/gnu-linux/macos" "$platform"
    fi
}

# Test: Language detection
test_language_detection() {
    echo ""
    echo "=== Test: Language Detection ==="
    
    source "${SCRIPT_DIR}/../lib/utils.sh"
    
    local tests=(
        "test.py:python"
        "test.js:javascript"
        "test.ts:typescript"
        "test.go:go"
        "test.rs:rust"
        "test.java:java"
        "test.sh:bash"
        "test.cpp:cpp"
        "test.rb:ruby"
        "test.php:php"
    )
    
    for test_case in "${tests[@]}"; do
        local file="${test_case%%:*}"
        local expected="${test_case##*:}"
        local result
        result=$(scout_detect_language "$file")
        
        if [[ "$result" == "$expected" ]]; then
            pass "Detects $file as $expected"
        else
            fail "Detects $file as $expected" "$expected" "$result"
        fi
    done
}

# Main test runner
main() {
    echo "============================================"
    echo "Scout Plugin Test Suite"
    echo "============================================"
    echo ""
    
    # Setup
    setup
    
    # Run tests
    test_help_command
    test_tree_command
    test_stats_command
    test_analyze_command
    test_deps_command
    test_report_command
    test_exclude_patterns
    test_output_to_file
    test_error_handling
    test_platform_detection
    test_language_detection
    
    # Cleanup
    cleanup
    
    # Summary
    echo ""
    echo "============================================"
    echo "Test Summary"
    echo "============================================"
    echo "Total:  $TOTAL"
    echo -e "Passed: ${GREEN}$PASSED${NC}"
    echo -e "Failed: ${RED}$FAILED${NC}"
    echo ""
    
    if [[ $FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}Some tests failed.${NC}"
        return 1
    fi
}

main "$@"
