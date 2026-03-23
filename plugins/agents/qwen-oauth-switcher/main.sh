#!/usr/bin/env bash
# Qwen OAuth Switcher - Multi-account credential manager
#
# Usage:
#   qwen-oauth list              # List all accounts
#   qwen-oauth add <name>        # Add new account
#   qwen-oauth switch <name>     # Switch to account
#   qwen-oauth current           # Show current account
#   qwen-oauth remove <name>     # Remove account
#   qwen-oauth refresh           # Refresh current token
#   qwen-oauth stats             # Show usage statistics
#   qwen-oauth health            # Health check

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_NAME="qwen-oauth-switcher"

# Configuration
QWEN_OAUTH_DIR="${QWEN_OAUTH_DIR:-${HOME}/.oml/qwen-oauth}"
CREDENTIALS_FILE="${QWEN_OAUTH_DIR}/credentials.json"
CURRENT_ACCOUNT_FILE="${QWEN_OAUTH_DIR}/current_account"
STATS_FILE="${QWEN_OAUTH_DIR}/stats.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Initialize storage directory
init_storage() {
    mkdir -p "${QWEN_OAUTH_DIR}"
    chmod 700 "${QWEN_OAUTH_DIR}"
    
    if [[ ! -f "${CREDENTIALS_FILE}" ]]; then
        echo '{}' > "${CREDENTIALS_FILE}"
        chmod 600 "${CREDENTIALS_FILE}"
    fi
    
    if [[ ! -f "${STATS_FILE}" ]]; then
        echo '{"total_requests": 0, "accounts": {}}' > "${STATS_FILE}"
        chmod 600 "${STATS_FILE}"
    fi
}

# Encode credentials (Base64)
encode_credentials() {
    local data="$1"
    echo -n "$data" | base64 -w 0
}

# Decode credentials
decode_credentials() {
    local encoded="$1"
    echo -n "$encoded" | base64 -d
}

# Mask API key for display
mask_key() {
    local key="$1"
    if [[ ${#key} -le 10 ]]; then
        echo "***"
    else
        echo "${key:0:6}...${key: -4}"
    fi
}

# Add new account
cmd_add() {
    local name="${1:-}"
    
    if [[ -z "$name" ]]; then
        echo -e "${RED}Error: Account name required${NC}"
        echo "Usage: qwen-oauth add <name>"
        return 1
    fi
    
    echo -e "${BLUE}Adding new account: ${name}${NC}"
    echo ""
    
    # Get credentials
    read -p "Enter Qwen API Key: " -s api_key
    echo ""
    read -p "Enter Base URL (optional, press Enter for default): " base_url
    base_url="${base_url:-https://dashscope.aliyuncs.com/compatible-mode/v1}"
    
    # Encode and store
    local encoded_key
    encoded_key=$(encode_credentials "$api_key")
    
    # Update credentials file
    local temp_file
    temp_file=$(mktemp)
    
    jq --arg name "$name" \
       --arg key "$encoded_key" \
       --arg url "$base_url" \
       --arg added "$(date -Iseconds)" \
       '.[$name] = {
           "api_key": $key,
           "base_url": $url,
           "added_at": $added,
           "last_used": null,
           "token_expires": null
       }' "${CREDENTIALS_FILE}" > "$temp_file"
    
    mv "$temp_file" "${CREDENTIALS_FILE}"
    chmod 600 "${CREDENTIALS_FILE}"
    
    # Update stats
    jq --arg name "$name" \
       '.accounts[$name] = {
           "requests": 0,
           "last_request": null
       }' "${STATS_FILE}" > "$temp_file"
    
    mv "$temp_file" "${STATS_FILE}"
    
    echo -e "${GREEN}✓ Account added successfully${NC}"
    echo ""
    echo "Account: ${name}"
    echo "Base URL: ${base_url}"
    echo "API Key: $(mask_key "$api_key")"
}

# List all accounts
cmd_list() {
    echo -e "${BLUE}Configured Accounts:${NC}"
    echo ""
    
    local current
    current=$(cat "${CURRENT_ACCOUNT_FILE}" 2>/dev/null || echo "")
    
    jq -r 'to_entries[] | "\(.key)|\(.value.base_url)|\(.value.added_at)"' "${CREDENTIALS_FILE}" | \
    while IFS='|' read -r name url added; do
        local marker="  "
        if [[ "$name" == "$current" ]]; then
            marker="* "
        fi
        
        echo -e "${marker}${GREEN}${name}${NC}"
        echo "   URL: ${url}"
        echo "   Added: ${added}"
        echo ""
    done
    
    if [[ -n "$current" ]]; then
        echo -e "${BLUE}Current account: ${GREEN}${current}${NC}"
    fi
}

# Switch account
cmd_switch() {
    local name="${1:-}"
    
    if [[ -z "$name" ]]; then
        echo -e "${RED}Error: Account name required${NC}"
        echo "Usage: qwen-oauth switch <name>"
        return 1
    fi
    
    # Check if account exists
    if ! jq -e --arg name "$name" 'has($name)' "${CREDENTIALS_FILE}" > /dev/null; then
        echo -e "${RED}Error: Account '${name}' not found${NC}"
        return 1
    fi
    
    # Switch
    echo "$name" > "${CURRENT_ACCOUNT_FILE}"
    chmod 600 "${CURRENT_ACCOUNT_FILE}"
    
    # Update stats
    local temp_file
    temp_file=$(mktemp)
    jq --arg name "$name" \
       --arg time "$(date -Iseconds)" \
       '.accounts[$name].last_used = $time' "${STATS_FILE}" > "$temp_file"
    mv "$temp_file" "${STATS_FILE}"
    
    # Export environment variables
    local api_key base_url
    api_key=$(jq -r --arg name "$name" '.[$name].api_key' "${CREDENTIALS_FILE}")
    base_url=$(jq -r --arg name "$name" '.[$name].base_url' "${CREDENTIALS_FILE}")
    
    echo -e "${GREEN}✓ Switched to account: ${name}${NC}"
    echo ""
    echo "To use in current shell, run:"
    echo "  export QWEN_API_KEY=\"$(decode_credentials "$api_key" | mask_key "$(decode_credentials "$api_key")")\""
    echo "  export QWEN_BASE_URL=\"${base_url}\""
}

# Show current account
cmd_current() {
    local current
    current=$(cat "${CURRENT_ACCOUNT_FILE}" 2>/dev/null || echo "")
    
    if [[ -z "$current" ]]; then
        echo -e "${YELLOW}No active account${NC}"
        echo "Use 'qwen-oauth switch <name>' to activate an account"
        return 0
    fi
    
    if ! jq -e --arg name "$current" 'has($name)' "${CREDENTIALS_FILE}" > /dev/null; then
        echo -e "${RED}Current account '${current}' not found in credentials${NC}"
        return 1
    fi
    
    local api_key base_url added last_used
    api_key=$(jq -r --arg name "$current" '.[$name].api_key' "${CREDENTIALS_FILE}")
    base_url=$(jq -r --arg name "$current" '.[$name].base_url' "${CREDENTIALS_FILE}")
    added=$(jq -r --arg name "$current" '.[$name].added_at' "${CREDENTIALS_FILE}")
    last_used=$(jq -r --arg name "$current" '.[$name].last_used // "N/A"' "${CREDENTIALS_FILE}")
    
    echo -e "${BLUE}Current Account:${NC}"
    echo ""
    echo -e "  Name: ${GREEN}${current}${NC}"
    echo "  Base URL: ${base_url}"
    echo "  API Key: $(mask_key "$(decode_credentials "$api_key")")"
    echo "  Added: ${added}"
    echo "  Last Used: ${last_used}"
}

# Remove account
cmd_remove() {
    local name="${1:-}"
    
    if [[ -z "$name" ]]; then
        echo -e "${RED}Error: Account name required${NC}"
        echo "Usage: qwen-oauth remove <name>"
        return 1
    fi
    
    # Check if account exists
    if ! jq -e --arg name "$name" 'has($name)' "${CREDENTIALS_FILE}" > /dev/null; then
        echo -e "${RED}Error: Account '${name}' not found${NC}"
        return 1
    fi
    
    # Remove from credentials
    local temp_file
    temp_file=$(mktemp)
    jq --arg name "$name" 'del(.[$name])' "${CREDENTIALS_FILE}" > "$temp_file"
    mv "$temp_file" "${CREDENTIALS_FILE}"
    
    # Remove from stats
    jq --arg name "$name" 'del(.accounts[$name])' "${STATS_FILE}" > "$temp_file"
    mv "$temp_file" "${STATS_FILE}"
    
    # Clear current if needed
    local current
    current=$(cat "${CURRENT_ACCOUNT_FILE}" 2>/dev/null || echo "")
    if [[ "$current" == "$name" ]]; then
        rm -f "${CURRENT_ACCOUNT_FILE}"
    fi
    
    echo -e "${GREEN}✓ Account removed: ${name}${NC}"
}

# Refresh token (placeholder for OAuth flow)
cmd_refresh() {
    local current
    current=$(cat "${CURRENT_ACCOUNT_FILE}" 2>/dev/null || echo "")
    
    if [[ -z "$current" ]]; then
        echo -e "${RED}Error: No active account${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Refreshing token for: ${current}${NC}"
    echo ""
    echo "Note: Current implementation uses API keys."
    echo "OAuth token refresh will be implemented in future versions."
}

# Show usage statistics
cmd_stats() {
    echo -e "${BLUE}Usage Statistics:${NC}"
    echo ""
    
    # Total requests
    local total
    total=$(jq -r '.total_requests' "${STATS_FILE}")
    echo "Total Requests: ${total}"
    echo ""
    
    # Per-account stats
    echo "Per-Account Stats:"
    jq -r '.accounts | to_entries[] | "  \(.key): \(.value.requests) requests"' "${STATS_FILE}"
}

# Health check
cmd_health() {
    local current
    current=$(cat "${CURRENT_ACCOUNT_FILE}" 2>/dev/null || echo "")
    
    if [[ -z "$current" ]]; then
        echo -e "${RED}✗ No active account${NC}"
        return 1
    fi
    
    local api_key base_url
    api_key=$(jq -r --arg name "$current" '.[$name].api_key' "${CREDENTIALS_FILE}")
    base_url=$(jq -r --arg name "$current" '.[$name].base_url' "${CREDENTIALS_FILE}")
    
    echo -e "${BLUE}Health Check for: ${current}${NC}"
    echo ""
    
    # Check API connectivity
    echo "Testing API connectivity..."
    
    local response
    response=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer $(decode_credentials "$api_key")" \
        "${base_url}/models" 2>/dev/null || echo "000")
    
    case "$response" in
        200)
            echo -e "${GREEN}✓ API connection successful${NC}"
            ;;
        401)
            echo -e "${RED}✗ Authentication failed${NC}"
            echo "  Please check your API key"
            return 1
            ;;
        403)
            echo -e "${RED}✗ Access forbidden${NC}"
            echo "  API key may be expired or revoked"
            return 1
            ;;
        000)
            echo -e "${RED}✗ Connection failed${NC}"
            echo "  Check your network connection"
            return 1
            ;;
        *)
            echo -e "${YELLOW}⚠ Unexpected response: ${response}${NC}"
            ;;
    esac
}

# Show help
show_help() {
    cat <<EOF
Qwen OAuth Switcher - Multi-account credential manager

Usage: qwen-oauth <command> [args]

Commands:
  list              List all configured accounts
  add <name>        Add new OAuth account
  switch <name>     Switch to specified account
  current           Show current active account
  remove <name>     Remove OAuth account
  refresh           Refresh access token
  stats             Show usage statistics
  health            Health check for current account
  help              Show this help message

Examples:
  qwen-oauth add work           # Add work account
  qwen-oauth add personal       # Add personal account
  qwen-oauth list               # List all accounts
  qwen-oauth switch work        # Switch to work account
  qwen-oauth current            # Show current account
  qwen-oauth health             # Check API connectivity
  qwen-oauth stats              # Show usage stats
  qwen-oauth remove old         # Remove old account

Security:
  - Credentials are stored in ~/.oml/qwen-oauth/
  - API keys are Base64 encoded
  - Directory permissions: 700 (owner only)
  - File permissions: 600 (owner read/write only)

EOF
}

# Main entry point
main() {
    init_storage
    
    local command="${1:-help}"
    shift || true
    
    case "$command" in
        list)
            cmd_list
            ;;
        add)
            cmd_add "$@"
            ;;
        switch)
            cmd_switch "$@"
            ;;
        current)
            cmd_current
            ;;
        remove)
            cmd_remove "$@"
            ;;
        refresh)
            cmd_refresh
            ;;
        stats)
            cmd_stats
            ;;
        health)
            cmd_health
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}Unknown command: $command${NC}"
            echo "Use 'qwen-oauth help' for usage"
            return 1
            ;;
    esac
}

main "$@"
