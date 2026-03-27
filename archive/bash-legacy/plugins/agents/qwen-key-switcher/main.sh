#!/usr/bin/env bash
# Qwen Key Switcher - Manage multiple free API keys
#
# Storage: ~/.oml/qwen-keys/
#   - keys.json: Encrypted API keys storage
#   - current: Current active key index
#   - stats.json: Usage statistics
#
# Usage:
#   qwen-key list              # List all keys
#   qwen-key add <key>         # Add new key
#   qwen-key use <index>       # Use specified key
#   qwen-key current           # Show current key
#   qwen-key remove <index>    # Remove key
#   qwen-key rotate            # Rotate to next key
#   qwen-key stats             # Show statistics
#   qwen-key health            # Health check all keys
#   qwen-key export            # Export to environment

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_NAME="qwen-key-switcher"

# Configuration
QWEN_KEY_DIR="${QWEN_KEY_DIR:-${HOME}/.oml/qwen-keys}"
KEYS_FILE="${QWEN_KEY_DIR}/keys.json"
CURRENT_FILE="${QWEN_KEY_DIR}/current"
STATS_FILE="${QWEN_KEY_DIR}/stats.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Initialize storage
init_storage() {
    mkdir -p "${QWEN_KEY_DIR}"
    chmod 700 "${QWEN_KEY_DIR}"
    
    if [[ ! -f "${KEYS_FILE}" ]]; then
        echo '[]' > "${KEYS_FILE}"
        chmod 600 "${KEYS_FILE}"
    fi
    
    if [[ ! -f "${STATS_FILE}" ]]; then
        echo '{"total_requests": 0, "keys": []}' > "${STATS_FILE}"
        chmod 600 "${STATS_FILE}"
    fi
}

# Encode key (Base64)
encode_key() {
    echo -n "$1" | base64 -w 0
}

# Decode key
decode_key() {
    echo -n "$1" | base64 -d
}

# Mask key for display (sk-***abcd)
mask_key() {
    local key="$1"
    if [[ ${#key} -le 10 ]]; then
        echo "sk-***"
    else
        echo "sk-***${key: -4}"
    fi
}

# Get key count
get_key_count() {
    jq 'length' "${KEYS_FILE}"
}

# Add new key
cmd_add() {
    local key="${1:-}"
    local name="${2:-}"
    
    if [[ -z "$key" ]]; then
        echo -e "${RED}Error: API key required${NC}"
        echo "Usage: qwen-key add <key> [name]"
        return 1
    fi
    
    # Validate key format
    if [[ ! "$key" =~ ^sk- ]]; then
        echo -e "${YELLOW}Warning: Key doesn't start with 'sk-'${NC}"
    fi
    
    # Encode key
    local encoded
    encoded=$(encode_key "$key")
    
    # Generate name if not provided
    if [[ -z "$name" ]]; then
        name="key_$(date +%s)"
    fi
    
    # Add to storage
    local temp_file
    temp_file=$(mktemp)
    
    jq --arg key "$encoded" \
       --arg name "$name" \
       --arg added "$(date -Iseconds)" \
       '. += [{
           "key": $key,
           "name": $name,
           "added_at": $added,
           "last_used": null,
           "request_count": 0,
           "status": "active"
       }]' "${KEYS_FILE}" > "$temp_file"
    
    mv "$temp_file" "${KEYS_FILE}"
    chmod 600 "${KEYS_FILE}"
    
    # Initialize stats
    local index
    index=$(get_key_count)
    index=$((index - 1))
    
    jq --argjson idx "$index" \
       '.keys[$idx] = {"requests": 0, "last_request": null}' "${STATS_FILE}" > "$temp_file"
    mv "$temp_file" "${STATS_FILE}"
    
    echo -e "${GREEN}✓ Key added successfully${NC}"
    echo ""
    echo "Index: ${index}"
    echo "Name: ${name}"
    echo "Key: $(mask_key "$key")"
    echo ""
    echo "To activate this key, run:"
    echo "  qwen-key use ${index}"
}

# List all keys
cmd_list() {
    echo -e "${BLUE}Stored API Keys:${NC}"
    echo ""
    
    local current
    current=$(cat "${CURRENT_FILE}" 2>/dev/null || echo "-1")
    
    local count
    count=$(get_key_count)
    
    if [[ "$count" -eq 0 ]]; then
        echo "  No keys stored"
        echo ""
        echo "To add a key, run:"
        echo "  qwen-key add sk-xxxxx [name]"
        return 0
    fi
    
    jq -r '.[] | "\(.key)|\(.name)|\(.added_at)|\(.status)"' "${KEYS_FILE}" | \
    nl -v 0 | while IFS='|' read -r idx encoded name added status; do
        local marker="  "
        if [[ "$idx" == "$current" ]]; then
            marker="* "
        fi
        
        local key
        key=$(decode_key "$encoded")
        
        echo -e "${marker}${GREEN}${idx}${NC}: ${name}"
        echo "      Key: $(mask_key "$key")"
        echo "      Added: ${added}"
        echo "      Status: ${status}"
        echo ""
    done
    
    if [[ "$current" != "-1" ]]; then
        echo -e "${BLUE}Current key index: ${GREEN}${current}${NC}"
    fi
}

# Use specified key
cmd_use() {
    local index="${1:-}"
    
    if [[ -z "$index" ]]; then
        echo -e "${RED}Error: Key index required${NC}"
        echo "Usage: qwen-key use <index>"
        return 1
    fi
    
    local count
    count=$(get_key_count)
    
    if [[ "$index" -lt 0 ]] || [[ "$index" -ge "$count" ]]; then
        echo -e "${RED}Error: Invalid index ${index}${NC}"
        echo "Valid range: 0-$((count - 1))"
        return 1
    fi
    
    # Save current index
    echo "$index" > "${CURRENT_FILE}"
    chmod 600 "${CURRENT_FILE}"
    
    # Update key last_used
    local temp_file
    temp_file=$(mktemp)
    jq --argjson idx "$index" \
       --arg time "$(date -Iseconds)" \
       '.[$idx].last_used = $time' "${KEYS_FILE}" > "$temp_file"
    mv "$temp_file" "${KEYS_FILE}"
    
    # Get key and export
    local encoded base_url
    encoded=$(jq -r --argjson idx "$index" '.[$idx].key' "${KEYS_FILE}")
    base_url=$(jq -r --argjson idx "$index" '.[$idx].base_url // "https://dashscope.aliyuncs.com/compatible-mode/v1"' "${KEYS_FILE}")
    
    local key
    key=$(decode_key "$encoded")
    
    echo -e "${GREEN}✓ Switched to key ${index}${NC}"
    echo ""
    echo "Key: $(mask_key "$key")"
    echo "Base URL: ${base_url}"
    echo ""
    echo "To use in current shell, run:"
    echo "  eval \$(qwen-key export)"
    echo ""
    echo "Or the key will be auto-exported when using 'oml qwen' command"
}

# Show current key
cmd_current() {
    local index
    index=$(cat "${CURRENT_FILE}" 2>/dev/null || echo "-1")
    
    if [[ "$index" == "-1" ]]; then
        echo -e "${YELLOW}No active key${NC}"
        echo "Use 'qwen-key use <index>' to activate a key"
        return 0
    fi
    
    local count
    count=$(get_key_count)
    
    if [[ "$index" -ge "$count" ]]; then
        echo -e "${RED}Current index ${index} is invalid${NC}"
        echo "Use 'qwen-key list' to see available keys"
        return 1
    fi
    
    local encoded name added last_used base_url
    encoded=$(jq -r --argjson idx "$index" '.[$idx].key' "${KEYS_FILE}")
    name=$(jq -r --argjson idx "$index" '.[$idx].name' "${KEYS_FILE}")
    added=$(jq -r --argjson idx "$index" '.[$idx].added_at' "${KEYS_FILE}")
    last_used=$(jq -r --argjson idx "$index" '.[$idx].last_used // "N/A"' "${KEYS_FILE}")
    base_url=$(jq -r --argjson idx "$index" '.[$idx].base_url // "default"' "${KEYS_FILE}")
    
    local key
    key=$(decode_key "$encoded")
    
    echo -e "${BLUE}Current API Key:${NC}"
    echo ""
    echo -e "  Index: ${GREEN}${index}${NC}"
    echo "  Name: ${name}"
    echo "  Key: $(mask_key "$key")"
    echo "  Base URL: ${base_url}"
    echo "  Added: ${added}"
    echo "  Last Used: ${last_used}"
}

# Remove key
cmd_remove() {
    local index="${1:-}"
    
    if [[ -z "$index" ]]; then
        echo -e "${RED}Error: Key index required${NC}"
        echo "Usage: qwen-key remove <index>"
        return 1
    fi
    
    local count
    count=$(get_key_count)
    
    if [[ "$index" -lt 0 ]] || [[ "$index" -ge "$count" ]]; then
        echo -e "${RED}Error: Invalid index ${index}${NC}"
        return 1
    fi
    
    # Remove from keys
    local temp_file
    temp_file=$(mktemp)
    jq --argjson idx "$index" 'del(.[$idx])' "${KEYS_FILE}" > "$temp_file"
    mv "$temp_file" "${KEYS_FILE}"
    
    # Clear current if needed
    local current
    current=$(cat "${CURRENT_FILE}" 2>/dev/null || echo "")
    if [[ "$current" == "$index" ]]; then
        rm -f "${CURRENT_FILE}"
    fi
    
    echo -e "${GREEN}✓ Key removed: index ${index}${NC}"
}

# Rotate to next key
cmd_rotate() {
    local count
    count=$(get_key_count)
    
    if [[ "$count" -eq 0 ]]; then
        echo -e "${RED}Error: No keys stored${NC}"
        return 1
    fi
    
    local current
    current=$(cat "${CURRENT_FILE}" 2>/dev/null || echo "-1")
    
    local next_index
    if [[ "$current" == "-1" ]] || [[ "$current" -ge $((count - 1)) ]]; then
        next_index=0
    else
        next_index=$((current + 1))
    fi
    
    # Use next key
    cmd_use "$next_index"
}

# Show statistics
cmd_stats() {
    echo -e "${BLUE}Usage Statistics:${NC}"
    echo ""
    
    # Total requests
    local total
    total=$(jq -r '.total_requests' "${STATS_FILE}")
    echo "Total Requests: ${total}"
    echo ""
    
    # Per-key stats
    echo "Per-Key Stats:"
    jq -r '.keys | to_entries[] | "  Key \(.key): \(.value.requests) requests"' "${STATS_FILE}"
}

# Health check all keys
cmd_health() {
    echo -e "${BLUE}Health Check:${NC}"
    echo ""
    
    local count
    count=$(get_key_count)
    
    if [[ "$count" -eq 0 ]]; then
        echo "  No keys to check"
        return 0
    fi
    
    for ((i=0; i<count; i++)); do
        local encoded base_url
        encoded=$(jq -r --argjson idx "$i" '.[$idx].key' "${KEYS_FILE}")
        base_url=$(jq -r --argjson idx "$i" '.[$idx].base_url // "https://dashscope.aliyuncs.com/compatible-mode/v1"' "${KEYS_FILE}")
        
        local key
        key=$(decode_key "$encoded")
        
        echo -n "  Key ${i} ($(mask_key "$key")): "
        
        # Test API connectivity
        local response
        response=$(curl -s -o /dev/null -w "%{http_code}" \
            -H "Authorization: Bearer ${key}" \
            "${base_url}/models" 2>/dev/null || echo "000")
        
        case "$response" in
            200)
                echo -e "${GREEN}✓ OK${NC}"
                ;;
            401)
                echo -e "${RED}✗ Auth failed${NC}"
                ;;
            403)
                echo -e "${RED}✗ Forbidden${NC}"
                ;;
            429)
                echo -e "${YELLOW}⚠ Rate limited${NC}"
                ;;
            000)
                echo -e "${RED}✗ Connection failed${NC}"
                ;;
            *)
                echo -e "${YELLOW}⚠ Status: ${response}${NC}"
                ;;
        esac
    done
}

# Export to environment
cmd_export() {
    local index
    index=$(cat "${CURRENT_FILE}" 2>/dev/null || echo "-1")
    
    if [[ "$index" == "-1" ]]; then
        echo -e "${RED}Error: No active key${NC}"
        return 1
    fi
    
    local encoded base_url
    encoded=$(jq -r --argjson idx "$index" '.[$idx].key' "${KEYS_FILE}")
    base_url=$(jq -r --argjson idx "$index" '.[$idx].base_url // "https://dashscope.aliyuncs.com/compatible-mode/v1"' "${KEYS_FILE}")
    
    local key
    key=$(decode_key "$encoded")
    
    # Export commands
    echo "export QWEN_API_KEY='${key}'"
    echo "export QWEN_BASE_URL='${base_url}'"
}

# Show help
show_help() {
    cat <<EOF
Qwen Key Switcher - Manage multiple free API keys

Usage: qwen-key <command> [args]

Commands:
  list              List all stored API keys
  add <key> [name]  Add new API key
  use <index>       Switch to specified key
  current           Show current active key
  remove <index>    Remove API key
  rotate            Rotate to next key
  stats             Show usage statistics
  health            Health check all keys
  export            Export current key to environment
  help              Show this help message

Examples:
  qwen-key add sk-xxxxx work         # Add work key
  qwen-key add sk-yyyyy personal     # Add personal key
  qwen-key list                      # List all keys
  qwen-key use 0                     # Use first key
  qwen-key rotate                    # Rotate to next key
  qwen-key current                   # Show current key
  qwen-key health                    # Check all keys
  eval \$(qwen-key export)           # Export to shell

Storage:
  Keys are stored in: ~/.oml/qwen-keys/
  - keys.json: Encrypted API keys (Base64)
  - current: Current active key index
  - stats.json: Usage statistics

Security:
  - Directory permissions: 700 (owner only)
  - File permissions: 600 (owner read/write)
  - Keys are Base64 encoded
  - Display shows masked keys (sk-***abcd)

Integration:
  When using 'oml qwen' command, the current key
  will be automatically exported to QWEN_API_KEY.

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
        use)
            cmd_use "$@"
            ;;
        current)
            cmd_current
            ;;
        remove)
            cmd_remove "$@"
            ;;
        rotate)
            cmd_rotate
            ;;
        stats)
            cmd_stats
            ;;
        health)
            cmd_health
            ;;
        export)
            cmd_export
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}Unknown command: $command${NC}"
            echo "Use 'qwen-key help' for usage"
            return 1
            ;;
    esac
}

main "$@"
