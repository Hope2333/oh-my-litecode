#!/usr/bin/env bash
# Test Suite for Reviewer Subagent Plugin
# Basic functionality tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
MAIN_SH="${PLUGIN_DIR}/main.sh"
TEST_DIR="${SCRIPT_DIR}/fixtures"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

log_info() { echo -e "${YELLOW}[INFO]${NC} $*"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $*"; ((TESTS_PASSED++)) || true; }
log_fail() { echo -e "${RED}[FAIL]${NC} $*"; ((TESTS_FAILED++)) || true; }

setup() {
    log_info "Setting up test fixtures..."
    mkdir -p "$TEST_DIR"

    # Security test file
    cat > "${TEST_DIR}/sec-test.js" <<'EOF'
const password = "secret123";
function test() {
    eval("code");
}
EOF

    # Style test file
    cat > "${TEST_DIR}/style-test.py" <<'EOF'
def very_long_function_name_that_exceeds_the_maximum_line_length_limit_and_should_be_flagged(param1):
    return param1
EOF

    # Clean file
    cat > "${TEST_DIR}/clean.js" <<'EOF'
/**
 * Add two numbers
 * @param {number} a
 * @param {number} b
 */
function add(a, b) { return a + b; }
module.exports = { add };
EOF
}

cleanup() {
    log_info "Cleaning up..."
    rm -rf "$TEST_DIR"
}

# Tests
test_help() {
    bash "$MAIN_SH" help 2>&1 | grep -q "OML Reviewer"
}

test_version() {
    bash "$MAIN_SH" version 2>&1 | grep -q "v0.1.0"
}

test_unknown_cmd() {
    local out
    out=$(bash "$MAIN_SH" unknown 2>&1)
    echo "$out" | grep -q "Unknown command"
}

test_security_single_file() {
    local out
    out=$(bash "$MAIN_SH" security "${TEST_DIR}/sec-test.js" --format json 2>&1)
    echo "$out" | jq -e '. | length >= 0' >/dev/null
}

test_security_detects_secrets() {
    local out
    out=$(bash "$MAIN_SH" security "${TEST_DIR}/sec-test.js" --format json 2>&1)
    echo "$out" | jq -e 'any(.[]; .severity == "critical")' >/dev/null
}

test_style_single_file() {
    local out
    out=$(bash "$MAIN_SH" style "${TEST_DIR}/style-test.py" --format json 2>&1)
    echo "$out" | jq -e '. | length >= 0' >/dev/null
}

test_performance_single_file() {
    local out
    out=$(bash "$MAIN_SH" performance "${TEST_DIR}/clean.js" --format json 2>&1)
    echo "$out" | jq -e '. | length >= 0' >/dev/null
}

test_best_practices_single_file() {
    local out
    out=$(bash "$MAIN_SH" best-practices "${TEST_DIR}/clean.js" --format json 2>&1)
    echo "$out" | jq -e '. | length >= 0' >/dev/null
}

test_code_single_file() {
    local out
    out=$(bash "$MAIN_SH" code "${TEST_DIR}/clean.js" --format json --quiet 2>&1)
    echo "$out" | jq -e '. | length >= 0' >/dev/null
}

test_clean_no_critical() {
    local out
    out=$(bash "$MAIN_SH" code "${TEST_DIR}/clean.js" --format json --quiet 2>&1)
    local crit
    crit=$(echo "$out" | jq '[.[] | select(.severity == "critical")] | length')
    [[ "$crit" -eq 0 ]]
}

test_report_quick() {
    local out
    out=$(bash "$MAIN_SH" report "${TEST_DIR}/clean.js" --quick --format json --quiet 2>&1)
    echo "$out" | jq -e '.health_score' >/dev/null
}

test_output_file() {
    local outfile="${TEST_DIR}/out.json"
    bash "$MAIN_SH" code "${TEST_DIR}/clean.js" --format json --output "$outfile" 2>&1
    [[ -f "$outfile" ]] && jq -e '.' "$outfile" >/dev/null
}

# Main
main() {
    log_info "Starting Reviewer Subagent Plugin Tests"
    echo "============================================"

    setup

    echo ""
    echo "--- Basic Command Tests ---"
    ((TESTS_RUN++)) || true
    log_info "Help command"
    test_help && log_pass "Help command" || log_fail "Help command"

    ((TESTS_RUN++)) || true
    log_info "Version command"
    test_version && log_pass "Version command" || log_fail "Version command"

    ((TESTS_RUN++)) || true
    log_info "Unknown command"
    test_unknown_cmd && log_pass "Unknown command" || log_fail "Unknown command"

    echo ""
    echo "--- Security Tests ---"
    ((TESTS_RUN++)) || true
    log_info "Security single file JSON"
    test_security_single_file && log_pass "Security single file JSON" || log_fail "Security single file JSON"

    ((TESTS_RUN++)) || true
    log_info "Security detects secrets"
    test_security_detects_secrets && log_pass "Security detects secrets" || log_fail "Security detects secrets"

    echo ""
    echo "--- Style Tests ---"
    ((TESTS_RUN++)) || true
    log_info "Style single file JSON"
    test_style_single_file && log_pass "Style single file JSON" || log_fail "Style single file JSON"

    echo ""
    echo "--- Performance Tests ---"
    ((TESTS_RUN++)) || true
    log_info "Performance single file JSON"
    test_performance_single_file && log_pass "Performance single file JSON" || log_fail "Performance single file JSON"

    echo ""
    echo "--- Best Practices Tests ---"
    ((TESTS_RUN++)) || true
    log_info "Best practices single file JSON"
    test_best_practices_single_file && log_pass "Best practices single file JSON" || log_fail "Best practices single file JSON"

    echo ""
    echo "--- Code Review Tests ---"
    ((TESTS_RUN++)) || true
    log_info "Code review single file"
    test_code_single_file && log_pass "Code review single file" || log_fail "Code review single file"

    ((TESTS_RUN++)) || true
    log_info "Clean file no critical"
    test_clean_no_critical && log_pass "Clean file no critical" || log_fail "Clean file no critical"

    echo ""
    echo "--- Report Tests ---"
    ((TESTS_RUN++)) || true
    log_info "Quick report"
    test_report_quick && log_pass "Quick report" || log_fail "Quick report"

    ((TESTS_RUN++)) || true
    log_info "Output to file"
    test_output_file && log_pass "Output to file" || log_fail "Output to file"

    cleanup

    echo ""
    echo "============================================"
    echo "Test Summary"
    echo "============================================"
    echo "Total:  $TESTS_RUN"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}Some tests failed.${NC}"
        return 1
    fi
}

main "$@"
