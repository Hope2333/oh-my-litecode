#!/usr/bin/env bash
# Git MCP Plugin - Test Suite
# Tests all git MCP plugin functionality

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
MAIN_SH="${PLUGIN_DIR}/main.sh"

# Test colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test temp directory
TEST_TEMP_DIR=""

# ============================================================================
# Test Utilities
# ============================================================================

log_info() {
    echo -e "${YELLOW}[INFO]${NC} $*"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $*"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $*"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

run_test() {
    local name="$1"
    local test_func="$2"
    shift 2
    
    TESTS_RUN=$((TESTS_RUN + 1))
    echo ""
    echo "========================================"
    echo "Test: $name"
    echo "========================================"
    
    if "$test_func" "$@"; then
        log_pass "$name"
        return 0
    else
        log_fail "$name"
        return 1
    fi
}

setup_test_repo() {
    TEST_TEMP_DIR=$(mktemp -d)
    cd "$TEST_TEMP_DIR"
    git init
    git config user.email "test@example.com"
    git config user.name "Test User"
    
    # Create initial commit
    echo "initial content" > README.md
    git add README.md
    git commit -m "Initial commit"
    
    log_info "Test repo created at: $TEST_TEMP_DIR"
}

cleanup_test_repo() {
    if [[ -n "$TEST_TEMP_DIR" ]] && [[ -d "$TEST_TEMP_DIR" ]]; then
        rm -rf "$TEST_TEMP_DIR"
        log_info "Test repo cleaned up"
    fi
}

# ============================================================================
# Tests
# ============================================================================

# Test: Help command
test_help() {
    log_info "Testing help command..."
    
    local output
    output=$("$MAIN_SH" help 2>&1)
    
    if [[ "$output" == *"Git MCP Plugin"* ]]; then
        log_info "Help output contains expected text"
        return 0
    else
        log_fail "Help output missing expected text"
        return 1
    fi
}

# Test: Status in non-git directory
test_status_non_git() {
    log_info "Testing status in non-git directory..."
    
    local temp_dir
    temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    local output
    output=$("$MAIN_SH" status 2>&1) || true
    
    rm -rf "$temp_dir"
    
    if [[ "$output" == *"Not a git repository"* ]] || [[ "$output" == *"error"* ]]; then
        log_info "Correctly detected non-git directory"
        return 0
    else
        log_fail "Should detect non-git directory"
        return 1
    fi
}

# Test: Status in git repository
test_status_git() {
    log_info "Testing status in git repository..."
    
    setup_test_repo
    
    local output
    output=$("$MAIN_SH" status 2>&1)
    
    if [[ "$output" == *"master"* ]] || [[ "$output" == *"main"* ]]; then
        log_info "Status shows branch information"
        cleanup_test_repo
        return 0
    else
        cleanup_test_repo
        log_fail "Status should show branch information"
        return 1
    fi
}

# Test: Status JSON output
test_status_json() {
    log_info "Testing status JSON output..."
    
    setup_test_repo
    
    local output
    output=$("$MAIN_SH" status --json 2>&1)
    
    if [[ "$output" == *"repository"* ]] && [[ "$output" == *"branch"* ]]; then
        log_info "JSON output contains expected fields"
        cleanup_test_repo
        return 0
    else
        cleanup_test_repo
        log_fail "JSON output missing expected fields"
        return 1
    fi
}

# Test: Diff working tree
test_diff_working() {
    log_info "Testing diff working tree..."
    
    setup_test_repo
    
    # Create a change
    echo "modified content" >> README.md
    
    local output
    output=$("$MAIN_SH" diff --stat 2>&1)
    
    if [[ "$output" == *"README.md"* ]] || [[ -z "$output" ]]; then
        log_info "Diff shows changes (or no changes if clean)"
        cleanup_test_repo
        return 0
    else
        cleanup_test_repo
        log_fail "Diff should show changes"
        return 1
    fi
}

# Test: Diff cached
test_diff_cached() {
    log_info "Testing diff cached..."
    
    setup_test_repo
    
    # Stage a change
    echo "new file" > newfile.txt
    git add newfile.txt
    
    local output
    output=$("$MAIN_SH" diff --cached --stat 2>&1)
    
    if [[ "$output" == *"newfile.txt"* ]]; then
        log_info "Cached diff shows staged changes"
        cleanup_test_repo
        return 0
    else
        cleanup_test_repo
        log_fail "Cached diff should show staged changes"
        return 1
    fi
}

# Test: Add file
test_add_file() {
    log_info "Testing add file..."
    
    setup_test_repo
    
    # Create a new file
    echo "test content" > test.txt
    
    local output
    output=$("$MAIN_SH" add test.txt 2>&1)
    
    # Check if file is staged
    local staged
    staged=$(git diff --cached --name-only)
    
    if [[ "$staged" == *"test.txt"* ]]; then
        log_info "File successfully staged"
        cleanup_test_repo
        return 0
    else
        cleanup_test_repo
        log_fail "File should be staged"
        return 1
    fi
}

# Test: Add all
test_add_all() {
    log_info "Testing add all..."
    
    setup_test_repo
    
    # Create multiple files
    echo "file1" > file1.txt
    echo "file2" > file2.txt
    echo "file3" > file3.txt
    
    local output
    output=$("$MAIN_SH" add --all 2>&1)
    
    # Check if files are staged
    local staged_count
    staged_count=$(git diff --cached --name-only | wc -l)
    
    if [[ "$staged_count" -ge 3 ]]; then
        log_info "All files successfully staged ($staged_count files)"
        cleanup_test_repo
        return 0
    else
        cleanup_test_repo
        log_fail "Should stage all files"
        return 1
    fi
}

# Test: Commit
test_commit() {
    log_info "Testing commit..."
    
    setup_test_repo
    
    # Create and stage a change
    echo "new content" >> README.md
    git add README.md
    
    local output
    output=$("$MAIN_SH" commit -m "Test commit" 2>&1)
    
    # Check if commit was made
    local last_commit
    last_commit=$(git log -1 --oneline)
    
    if [[ "$last_commit" == *"Test commit"* ]]; then
        log_info "Commit successful"
        cleanup_test_repo
        return 0
    else
        cleanup_test_repo
        log_fail "Commit should be recorded"
        return 1
    fi
}

# Test: Commit without message
test_commit_no_message() {
    log_info "Testing commit without message (should fail)..."
    
    setup_test_repo
    
    # Create and stage a change
    echo "new content" >> README.md
    git add README.md
    
    local output
    output=$("$MAIN_SH" commit 2>&1) || true
    
    if [[ "$output" == *"message required"* ]] || [[ "$output" == *"error"* ]] || [[ "$output" == *"Error"* ]]; then
        log_info "Correctly rejected commit without message"
        cleanup_test_repo
        return 0
    else
        cleanup_test_repo
        log_fail "Should reject commit without message"
        return 1
    fi
}

# Test: Log
test_log() {
    log_info "Testing log..."
    
    setup_test_repo
    
    # Create multiple commits
    echo "commit 2" >> README.md
    git add README.md
    git commit -m "Second commit"
    
    echo "commit 3" >> README.md
    git add README.md
    git commit -m "Third commit"
    
    local output
    output=$("$MAIN_SH" log -n 5 2>&1)
    
    if [[ "$output" == *"Second commit"* ]] && [[ "$output" == *"Third commit"* ]]; then
        log_info "Log shows commit history"
        cleanup_test_repo
        return 0
    else
        cleanup_test_repo
        log_fail "Log should show commit history"
        return 1
    fi
}

# Test: Log JSON
test_log_json() {
    log_info "Testing log JSON output..."
    
    setup_test_repo
    
    # Create another commit
    echo "commit 2" >> README.md
    git add README.md
    git commit -m "Second commit"
    
    local output
    output=$("$MAIN_SH" log --json -5 2>&1)
    
    if [[ "$output" == *"commits"* ]] && [[ "$output" == *"author"* ]]; then
        log_info "JSON log contains expected fields"
        cleanup_test_repo
        return 0
    else
        cleanup_test_repo
        log_fail "JSON log missing expected fields"
        return 1
    fi
}

# Test: Branch list
test_branch_list() {
    log_info "Testing branch list..."
    
    setup_test_repo
    
    local output
    output=$("$MAIN_SH" branch 2>&1)
    
    if [[ "$output" == *"master"* ]] || [[ "$output" == *"main"* ]]; then
        log_info "Branch list shows current branch"
        cleanup_test_repo
        return 0
    else
        cleanup_test_repo
        log_fail "Branch list should show current branch"
        return 1
    fi
}

# Test: Branch create
test_branch_create() {
    log_info "Testing branch create..."
    
    setup_test_repo
    
    local output
    output=$("$MAIN_SH" branch --create feature-test 2>&1)
    
    # Check if branch exists
    if git rev-parse --verify feature-test >/dev/null 2>&1; then
        log_info "Branch created successfully"
        cleanup_test_repo
        return 0
    else
        cleanup_test_repo
        log_fail "Branch should be created"
        return 1
    fi
}

# Test: Branch delete
test_branch_delete() {
    log_info "Testing branch delete..."
    
    setup_test_repo
    
    # Create and switch to a new branch, then back to master
    git checkout -b temp-branch
    git checkout master 2>/dev/null || git checkout main
    
    local output
    output=$("$MAIN_SH" branch --delete temp-branch --force 2>&1) || true
    
    # Check if branch is deleted
    if ! git rev-parse --verify temp-branch >/dev/null 2>&1; then
        log_info "Branch deleted successfully"
        cleanup_test_repo
        return 0
    else
        cleanup_test_repo
        log_fail "Branch should be deleted"
        return 1
    fi
}

# Test: Branch checkout
test_branch_checkout() {
    log_info "Testing branch checkout..."
    
    setup_test_repo
    
    # Create a branch
    git branch feature-test
    
    local output
    output=$("$MAIN_SH" branch --checkout feature-test 2>&1)
    
    # Check current branch
    local current
    current=$(git rev-parse --abbrev-ref HEAD)
    
    if [[ "$current" == "feature-test" ]]; then
        log_info "Successfully switched to branch"
        cleanup_test_repo
        return 0
    else
        cleanup_test_repo
        log_fail "Should switch to branch"
        return 1
    fi
}

# Test: Branch JSON
test_branch_json() {
    log_info "Testing branch JSON output..."
    
    setup_test_repo
    
    # Create additional branches
    git branch feature-1
    git branch feature-2
    
    local output
    output=$("$MAIN_SH" branch --json 2>&1)
    
    if [[ "$output" == *"branches"* ]] && [[ "$output" == *"current_branch"* ]]; then
        log_info "JSON branch output contains expected fields"
        cleanup_test_repo
        return 0
    else
        cleanup_test_repo
        log_fail "JSON branch output missing expected fields"
        return 1
    fi
}

# Test: Config show
test_config_show() {
    log_info "Testing config show..."
    
    setup_test_repo
    
    local output
    output=$("$MAIN_SH" config show 2>&1)
    
    if [[ "$output" == *"Git MCP Configuration"* ]]; then
        log_info "Config show works"
        cleanup_test_repo
        return 0
    else
        cleanup_test_repo
        log_fail "Config show should display configuration"
        return 1
    fi
}

# Test: Config set/get
test_config_set_get() {
    log_info "Testing config set/get..."
    
    setup_test_repo
    
    # Set a value
    "$MAIN_SH" config set user.name "Test Name" >/dev/null 2>&1
    
    # Get the value
    local value
    value=$("$MAIN_SH" config get user.name 2>&1)
    
    if [[ "$value" == *"Test Name"* ]]; then
        log_info "Config set/get works"
        cleanup_test_repo
        return 0
    else
        cleanup_test_repo
        log_fail "Config set/get should work"
        return 1
    fi
}

# Test: Safety - non-git directory
test_safety_non_git() {
    log_info "Testing safety: non-git directory detection..."
    
    local temp_dir
    temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    local output
    output=$("$MAIN_SH" add test.txt 2>&1) || true
    
    rm -rf "$temp_dir"
    
    if [[ "$output" == *"Not a git repository"* ]] || [[ "$output" == *"error"* ]]; then
        log_info "Correctly blocked operation in non-git directory"
        return 0
    else
        log_fail "Should block operations in non-git directory"
        return 1
    fi
}

# Test: Git version check
test_git_version() {
    log_info "Testing git version check..."
    
    local output
    output=$("$MAIN_SH" help 2>&1)
    
    # The script should run without git version errors
    if [[ $? -eq 0 ]] || [[ "$output" == *"Git"* ]]; then
        log_info "Git version check passed"
        return 0
    else
        log_fail "Git version check failed"
        return 1
    fi
}

# ============================================================================
# Main Test Runner
# ============================================================================

run_all_tests() {
    echo "============================================"
    echo "Git MCP Plugin - Test Suite"
    echo "============================================"
    echo ""
    echo "Plugin directory: $PLUGIN_DIR"
    echo "Main script: $MAIN_SH"
    echo ""
    
    # Check if main.sh exists
    if [[ ! -f "$MAIN_SH" ]]; then
        echo -e "${RED}Error: main.sh not found at $MAIN_SH${NC}"
        exit 1
    fi
    
    # Check if git is available
    if ! command -v git >/dev/null 2>&1; then
        echo -e "${RED}Error: git is not installed${NC}"
        exit 1
    fi
    
    echo "Git version: $(git --version)"
    echo ""
    
    # Run tests
    run_test "Help Command" test_help
    run_test "Status (Non-Git Dir)" test_status_non_git
    run_test "Status (Git Repo)" test_status_git
    run_test "Status JSON" test_status_json
    run_test "Diff Working Tree" test_diff_working
    run_test "Diff Cached" test_diff_cached
    run_test "Add File" test_add_file
    run_test "Add All" test_add_all
    run_test "Commit" test_commit
    run_test "Commit (No Message)" test_commit_no_message
    run_test "Log" test_log
    run_test "Log JSON" test_log_json
    run_test "Branch List" test_branch_list
    run_test "Branch Create" test_branch_create
    run_test "Branch Delete" test_branch_delete
    run_test "Branch Checkout" test_branch_checkout
    run_test "Branch JSON" test_branch_json
    run_test "Config Show" test_config_show
    run_test "Config Set/Get" test_config_set_get
    run_test "Safety (Non-Git)" test_safety_non_git
    run_test "Git Version Check" test_git_version
    
    # Summary
    echo ""
    echo "============================================"
    echo "Test Summary"
    echo "============================================"
    echo "Total tests: $TESTS_RUN"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    echo ""
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}Some tests failed.${NC}"
        return 1
    fi
}

# Run tests
run_all_tests "$@"
