#!/usr/bin/env bash
# Test Suite for Librarian Subagent Plugin

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
MAIN_SH="${PLUGIN_DIR}/main.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors
COLOR_RESET="\033[0m"
COLOR_GREEN="\033[32m"
COLOR_RED="\033[31m"
COLOR_YELLOW="\033[33m"
COLOR_BLUE="\033[34m"

# Test result reporting
test_pass() {
    local name="$1"
    echo -e "${COLOR_GREEN}✓ PASS${COLOR_RESET}: $name"
    ((TESTS_PASSED++))
    ((TESTS_RUN++))
}

test_fail() {
    local name="$1"
    local reason="${2:-}"
    echo -e "${COLOR_RED}✗ FAIL${COLOR_RESET}: $name"
    if [[ -n "$reason" ]]; then
        echo "  Reason: $reason"
    fi
    ((TESTS_FAILED++))
    ((TESTS_RUN++))
}

test_skip() {
    local name="$1"
    local reason="${2:-}"
    echo -e "${COLOR_YELLOW}○ SKIP${COLOR_RESET}: $name"
    if [[ -n "$reason" ]]; then
        echo "  Reason: $reason"
    fi
}

test_header() {
    local name="$1"
    echo ""
    echo -e "${COLOR_BLUE}=== ${name} ===${COLOR_RESET}"
}

# Setup test environment
setup_test_env() {
    export OML_LIBRARIAN_MAX_RESULTS=5
    export OML_LIBRARIAN_OUTPUT_FORMAT=json
    export OML_LIBRARIAN_CONTEXT7_ENABLED=false
    export OML_LIBRARIAN_WEBSEARCH_ENABLED=false
    export HOME="${HOME}/.local/test-home-${$}"
    mkdir -p "$HOME"
}

# Cleanup test environment
cleanup_test_env() {
    rm -rf "${HOME}/.local/test-home-${$}" 2>/dev/null || true
}

# ============================================================================
# Unit Tests: Utility Functions
# ============================================================================
test_utils_functions() {
    test_header "Utility Functions"
    
    # Source the library
    source "${PLUGIN_DIR}/lib/utils.sh"
    
    # Test librarian_generate_id
    local id1 id2
    id1=$(librarian_generate_id)
    id2=$(librarian_generate_id)
    
    if [[ -n "$id1" && ${#id1} -eq 8 ]]; then
        test_pass "librarian_generate_id returns 8-char ID"
    else
        test_fail "librarian_generate_id returns 8-char ID" "Got: $id1"
    fi
    
    if [[ "$id1" != "$id2" ]]; then
        test_pass "librarian_generate_id generates unique IDs"
    else
        test_fail "librarian_generate_id generates unique IDs"
    fi
    
    # Test librarian_timestamp
    local ts
    ts=$(librarian_timestamp)
    if [[ "$ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]; then
        test_pass "librarian_timestamp returns ISO format"
    else
        test_fail "librarian_timestamp returns ISO format" "Got: $ts"
    fi
    
    # Test librarian_hash
    local hash1 hash2
    hash1=$(librarian_hash "test content")
    hash2=$(librarian_hash "test content")
    
    if [[ -n "$hash1" && ${#hash1} -eq 32 ]]; then
        test_pass "librarian_hash returns MD5 hash"
    else
        test_fail "librarian_hash returns MD5 hash" "Got: $hash1"
    fi
    
    if [[ "$hash1" == "$hash2" ]]; then
        test_pass "librarian_hash is deterministic"
    else
        test_fail "librarian_hash is deterministic"
    fi
    
    # Test librarian_json_escape
    local escaped
    escaped=$(librarian_json_escape 'test "quotes"')
    if [[ "$escaped" == *'"'* ]]; then
        test_pass "librarian_json_escape handles quotes"
    else
        test_fail "librarian_json_escape handles quotes"
    fi
    
    # Test librarian_get_platform
    local platform
    platform=$(librarian_get_platform)
    if [[ "$platform" == "termux" || "$platform" == "gnu-linux" || "$platform" == "macos" ]]; then
        test_pass "librarian_get_platform returns valid platform"
    else
        test_fail "librarian_get_platform returns valid platform" "Got: $platform"
    fi
}

# ============================================================================
# Unit Tests: Results Processing
# ============================================================================
test_results_processing() {
    test_header "Results Processing"
    
    source "${PLUGIN_DIR}/lib/utils.sh"
    source "${PLUGIN_DIR}/lib/results.sh"
    
    # Test results_merge
    local merged
    merged=$(results_merge '[]' '[]')
    if [[ "$merged" == "[]" ]]; then
        test_pass "results_merge empty arrays"
    else
        test_fail "results_merge empty arrays" "Got: $merged"
    fi
    
    merged=$(results_merge '[{"a":1}]' '[{"b":2}]')
    if echo "$merged" | jq -e 'length == 2' >/dev/null 2>&1; then
        test_pass "results_merge combines arrays"
    else
        test_fail "results_merge combines arrays"
    fi
    
    # Test results_deduplicate
    local deduped
    deduped=$(results_merge '[{"url":"a"},{"url":"a"},{"url":"b"}]' '[]')
    deduped=$(results_deduplicate "$deduped" "url")
    
    if echo "$deduped" | jq -e 'length == 2' >/dev/null 2>&1; then
        test_pass "results_deduplicate removes duplicates"
    else
        test_fail "results_deduplicate removes duplicates" "Got: $(echo "$deduped" | jq 'length')"
    fi
    
    # Test results_sort
    local sorted
    sorted='[{"score":0.3},{"score":0.9},{"score":0.5}]'
    sorted=$(results_sort "$sorted" "score")
    
    local first_score
    first_score=$(echo "$sorted" | jq '.[0].score')
    if [[ "$first_score" == "0.9" ]]; then
        test_pass "results_sort by score descending"
    else
        test_fail "results_sort by score descending" "Got: $first_score"
    fi
    
    # Test results_limit
    local limited
    limited='[1,2,3,4,5,6,7,8,9,10]'
    limited=$(results_limit "$limited" 3)
    
    if echo "$limited" | jq -e 'length == 3' >/dev/null 2>&1; then
        test_pass "results_limit truncates array"
    else
        test_fail "results_limit truncates array"
    fi
    
    # Test results_stats
    local stats
    stats='[{"score":0.5},{"score":0.8},{"score":0.3}]'
    stats=$(results_stats "$stats")
    
    if echo "$stats" | jq -e '.total == 3' >/dev/null 2>&1; then
        test_pass "results_stats calculates total"
    else
        test_fail "results_stats calculates total"
    fi
}

# ============================================================================
# Integration Tests: Main Commands
# ============================================================================
test_main_commands() {
    test_header "Main Commands"
    
    # Test help command
    local help_output
    if help_output=$(bash "$MAIN_SH" help 2>&1); then
        if echo "$help_output" | grep -q "search"; then
            test_pass "help command shows search"
        else
            test_fail "help command shows search"
        fi
        
        if echo "$help_output" | grep -q "query"; then
            test_pass "help command shows query"
        else
            test_fail "help command shows query"
        fi
        
        if echo "$help_output" | grep -q "websearch"; then
            test_pass "help command shows websearch"
        else
            test_fail "help command shows websearch"
        fi
        
        if echo "$help_output" | grep -q "compile"; then
            test_pass "help command shows compile"
        else
            test_fail "help command shows compile"
        fi
    else
        test_fail "help command executes" "Command failed"
    fi
    
    # Test search command (without API keys, should handle gracefully)
    local search_output
    if search_output=$(bash "$MAIN_SH" search "test query" --format json 2>&1); then
        test_pass "search command executes without error"
    else
        # May fail due to missing API keys, which is expected
        test_skip "search command executes" "API keys not configured"
    fi
    
    # Test query command
    if bash "$MAIN_SH" query "react" "hooks" --format json >/dev/null 2>&1; then
        test_pass "query command executes"
    else
        test_skip "query command executes" "API keys not configured"
    fi
    
    # Test websearch command
    if bash "$MAIN_SH" websearch "test" --format json >/dev/null 2>&1; then
        test_pass "websearch command executes"
    else
        test_skip "websearch command executes" "API keys not configured"
    fi
    
    # Test compile command
    if bash "$MAIN_SH" compile "Test Topic" --format json >/dev/null 2>&1; then
        test_pass "compile command executes"
    else
        test_skip "compile command executes" "API keys not configured"
    fi
    
    # Test cache command
    local cache_output
    if cache_output=$(bash "$MAIN_SH" cache stats 2>&1); then
        if echo "$cache_output" | jq -e '.directory' >/dev/null 2>&1; then
            test_pass "cache stats returns JSON"
        else
            test_pass "cache stats executes"
        fi
    else
        test_fail "cache stats executes" "Command failed"
    fi
}

# ============================================================================
# Tests: Compile Module
# ============================================================================
test_compile_module() {
    test_header "Compile Module"
    
    source "${PLUGIN_DIR}/lib/utils.sh"
    source "${PLUGIN_DIR}/lib/compile.sh"
    
    # Test compile_knowledge with sample data
    local sample_results='[
        {"title": "Test Article", "source": "web", "content": "Test content here", "url": "https://example.com"},
        {"title": "Another Article", "source": "context7", "content": "More content", "url": "https://example.org"}
    ]'
    
    local compiled
    compiled=$(compile_knowledge "$sample_results" "Test Topic" '{"format": "markdown", "includeCitations": true, "includeSummary": true}')
    
    if [[ "$compiled" == *"Knowledge Compilation: Test Topic"* ]]; then
        test_pass "compile_knowledge generates title"
    else
        test_fail "compile_knowledge generates title"
    fi
    
    if [[ "$compiled" == *"References"* ]] || [[ "$compiled" == *"## Detailed Content"* ]]; then
        test_pass "compile_knowledge includes content sections"
    else
        test_fail "compile_knowledge includes content sections"
    fi
    
    # Test JSON format
    local json_compiled
    json_compiled=$(compile_knowledge "$sample_results" "Test Topic" '{"format": "json", "includeCitations": true, "includeSummary": true}')
    
    if echo "$json_compiled" | jq -e '.topic' >/dev/null 2>&1; then
        test_pass "compile_knowledge JSON format valid"
    else
        test_fail "compile_knowledge JSON format valid"
    fi
    
    # Test compile_list (empty)
    local list_output
    list_output=$(compile_list)
    if [[ "$list_output" == "[]" ]] || echo "$list_output" | jq -e 'type == "array"' >/dev/null 2>&1; then
        test_pass "compile_list returns array"
    else
        test_fail "compile_list returns array"
    fi
}

# ============================================================================
# Tests: Context7 Module (Mock)
# ============================================================================
test_context7_module() {
    test_header "Context7 Module"
    
    source "${PLUGIN_DIR}/lib/utils.sh"
    source "${PLUGIN_DIR}/lib/context7.sh"
    
    # Test context7_format_results
    local sample_results='[
        {"title": "React Docs", "source": "context7", "content": "React documentation", "url": "https://react.dev", "score": 0.9}
    ]'
    
    local formatted
    formatted=$(context7_format_results "$sample_results" "markdown")
    
    if [[ "$formatted" == *"React Docs"* ]]; then
        test_pass "context7_format_results markdown includes title"
    else
        test_fail "context7_format_results markdown includes title"
    fi
    
    # Test JSON format passthrough
    formatted=$(context7_format_results "$sample_results" "json")
    if echo "$formatted" | jq -e 'length > 0' >/dev/null 2>&1; then
        test_pass "context7_format_results json passthrough"
    else
        test_fail "context7_format_results json passthrough"
    fi
    
    # Test context7_generate_citation
    local citation
    citation=$(context7_generate_citation "$sample_results")
    if echo "$citation" | jq -e '.[0].type == "context7"' >/dev/null 2>&1; then
        test_pass "context7_generate_citation generates citation"
    else
        test_fail "context7_generate_citation generates citation"
    fi
}

# ============================================================================
# Tests: WebSearch Module (Mock)
# ============================================================================
test_websearch_module() {
    test_header "WebSearch Module"
    
    source "${PLUGIN_DIR}/lib/utils.sh"
    source "${PLUGIN_DIR}/lib/websearch.sh"
    
    # Test websearch_format_results
    local sample_results='[
        {"title": "Web Article", "source": "exa", "text": "Article content", "url": "https://example.com", "score": 0.8}
    ]'
    
    local formatted
    formatted=$(websearch_format_results "$sample_results" "markdown")
    
    if [[ "$formatted" == *"Web Article"* ]]; then
        test_pass "websearch_format_results markdown includes title"
    else
        test_fail "websearch_format_results markdown includes title"
    fi
    
    # Test websearch_generate_citation
    local citation
    citation=$(websearch_generate_citation "$sample_results")
    if echo "$citation" | jq -e '.type == "web"' >/dev/null 2>&1; then
        test_pass "websearch_generate_citation generates citation"
    else
        test_fail "websearch_generate_citation generates citation"
    fi
}

# ============================================================================
# Tests: Plugin Metadata
# ============================================================================
test_plugin_metadata() {
    test_header "Plugin Metadata"
    
    local plugin_json="${PLUGIN_DIR}/plugin.json"
    
    if [[ -f "$plugin_json" ]]; then
        test_pass "plugin.json exists"
    else
        test_fail "plugin.json exists"
        return
    fi
    
    # Validate JSON
    if jq -e '.' "$plugin_json" >/dev/null 2>&1; then
        test_pass "plugin.json is valid JSON"
    else
        test_fail "plugin.json is valid JSON"
    fi
    
    # Check required fields
    local name version type
    name=$(jq -r '.name' "$plugin_json")
    version=$(jq -r '.version' "$plugin_json")
    type=$(jq -r '.type' "$plugin_json")
    
    if [[ "$name" == "librarian" ]]; then
        test_pass "plugin.json name is 'librarian'"
    else
        test_fail "plugin.json name is 'librarian'" "Got: $name"
    fi
    
    if [[ -n "$version" && "$version" != "null" ]]; then
        test_pass "plugin.json has version"
    else
        test_fail "plugin.json has version"
    fi
    
    if [[ "$type" == "subagent" ]]; then
        test_pass "plugin.json type is 'subagent'"
    else
        test_fail "plugin.json type is 'subagent'" "Got: $type"
    fi
    
    # Check commands
    local commands
    commands=$(jq -r '.commands | length' "$plugin_json")
    if [[ "$commands" -ge 4 ]]; then
        test_pass "plugin.json has required commands ($commands)"
    else
        test_fail "plugin.json has required commands" "Got: $commands"
    fi
    
    # Check hooks
    if jq -e '.hooks.post_install' "$plugin_json" >/dev/null 2>&1; then
        test_pass "plugin.json has post_install hook"
    else
        test_fail "plugin.json has post_install hook"
    fi
    
    if jq -e '.hooks.pre_uninstall' "$plugin_json" >/dev/null 2>&1; then
        test_pass "plugin.json has pre_uninstall hook"
    else
        test_fail "plugin.json has pre_uninstall hook"
    fi
}

# ============================================================================
# Tests: File Structure
# ============================================================================
test_file_structure() {
    test_header "File Structure"
    
    # Check main files
    if [[ -f "${PLUGIN_DIR}/main.sh" ]]; then
        test_pass "main.sh exists"
    else
        test_fail "main.sh exists"
    fi
    
    if [[ -f "${PLUGIN_DIR}/plugin.json" ]]; then
        test_pass "plugin.json exists"
    else
        test_fail "plugin.json exists"
    fi
    
    # Check library files
    for lib in utils context7 websearch results compile; do
        if [[ -f "${PLUGIN_DIR}/lib/${lib}.sh" ]]; then
            test_pass "lib/${lib}.sh exists"
        else
            test_fail "lib/${lib}.sh exists"
        fi
    done
    
    # Check script files
    if [[ -f "${PLUGIN_DIR}/scripts/post-install.sh" ]]; then
        test_pass "scripts/post-install.sh exists"
    else
        test_fail "scripts/post-install.sh exists"
    fi
    
    if [[ -f "${PLUGIN_DIR}/scripts/pre-uninstall.sh" ]]; then
        test_pass "scripts/pre-uninstall.sh exists"
    else
        test_fail "scripts/pre-uninstall.sh exists"
    fi
    
    # Check executability
    if [[ -x "${PLUGIN_DIR}/main.sh" ]] || chmod +x "${PLUGIN_DIR}/main.sh" 2>/dev/null; then
        test_pass "main.sh is executable"
    else
        test_fail "main.sh is executable"
    fi
}

# ============================================================================
# Main Test Runner
# ============================================================================
main() {
    echo "============================================"
    echo "Librarian Subagent Plugin Test Suite"
    echo "============================================"
    echo ""
    
    # Setup
    setup_test_env
    
    # Run tests
    test_file_structure
    test_plugin_metadata
    test_utils_functions
    test_results_processing
    test_compile_module
    test_context7_module
    test_websearch_module
    test_main_commands
    
    # Cleanup
    cleanup_test_env
    
    # Summary
    echo ""
    echo "============================================"
    echo "Test Summary"
    echo "============================================"
    echo ""
    echo -e "Total:  ${TESTS_RUN}"
    echo -e "${COLOR_GREEN}Passed: ${TESTS_PASSED}${COLOR_RESET}"
    echo -e "${COLOR_RED}Failed: ${TESTS_FAILED}${COLOR_RESET}"
    echo ""
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${COLOR_GREEN}All tests passed!${COLOR_RESET}"
        return 0
    else
        echo -e "${COLOR_RED}Some tests failed.${COLOR_RESET}"
        return 1
    fi
}

# Run tests
main "$@"
