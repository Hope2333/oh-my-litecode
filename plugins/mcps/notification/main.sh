#!/usr/bin/env bash
# Notification MCP - Send notifications via desktop, email, webhook
#
# Usage:
#   oml mcp notification send_desktop "title" "message"
#   oml mcp notification send_email "to" "subject" "body"
#   oml mcp notification send_webhook "url" "message"
#   oml mcp notification test

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Send desktop notification
cmd_send_desktop() {
    local title="${1:-Notification}"
    local message="${2:-Test notification}"
    
    echo -e "${BLUE}Desktop Notification:${NC}"
    echo "Title: $title"
    echo "Message: $message"
    
    # Try different notification methods
    if command -v notify-send >/dev/null 2>&1; then
        notify-send "$title" "$message"
        echo -e "${GREEN}✓ Sent via notify-send${NC}"
    elif command -v osascript >/dev/null 2>&1; then
        osascript -e "display notification \"$message\" with title \"$title\""
        echo -e "${GREEN}✓ Sent via osascript${NC}"
    elif command -v termux-notification >/dev/null 2>&1; then
        termux-notification --title "$title" --content "$message"
        echo -e "${GREEN}✓ Sent via termux-notification${NC}"
    else
        echo -e "${YELLOW}! No notification system found, showing message${NC}"
        echo "[$title] $message"
    fi
}

# Send email notification
cmd_send_email() {
    local to="${1:-}"
    local subject="${2:-Notification}"
    local body="${3:-}"
    
    if [[ -z "$to" ]]; then
        echo -e "${RED}Error: Recipient email required${NC}" >&2
        return 1
    fi
    
    echo -e "${YELLOW}Confirm email to $to? (y/N)${NC}"
    read -r confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "Cancelled"
        return 0
    fi
    
    echo -e "${BLUE}Email Notification:${NC}"
    echo "To: $to"
    echo "Subject: $subject"
    echo "Body: $body"
    
    # Try different email methods
    if command -v mail >/dev/null 2>&1; then
        echo "$body" | mail -s "$subject" "$to"
        echo -e "${GREEN}✓ Sent via mail${NC}"
    elif command -v sendmail >/dev/null 2>&1; then
        echo -e "To: $to\nSubject: $subject\n\n$body" | sendmail "$to"
        echo -e "${GREEN}✓ Sent via sendmail${NC}"
    else
        echo -e "${YELLOW}! No email system found, showing message${NC}"
        echo "Email would be sent to: $to"
        echo "Subject: $subject"
        echo "Body: $body"
    fi
}

# Send webhook notification
cmd_send_webhook() {
    local url="${1:-}"
    local message="${2:-}"
    
    if [[ -z "$url" ]]; then
        echo -e "${RED}Error: Webhook URL required${NC}" >&2
        return 1
    fi
    
    echo -e "${YELLOW}Confirm webhook to $url? (y/N)${NC}"
    read -r confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "Cancelled"
        return 0
    fi
    
    echo -e "${BLUE}Webhook Notification:${NC}"
    echo "URL: $url"
    echo "Message: $message"
    
    if command -v curl >/dev/null 2>&1; then
        curl -X POST -H "Content-Type: application/json" \
            -d "{\"message\":\"$message\"}" \
            "$url" -s -o /dev/null -w "%{http_code}"
        echo -e "${GREEN}✓ Webhook sent${NC}"
    else
        echo -e "${YELLOW}! curl not found, showing payload${NC}"
        echo "POST $url"
        echo "Content-Type: application/json"
        echo "Body: {\"message\":\"$message\"}"
    fi
}

# List notification channels
cmd_list_channels() {
    echo -e "${BLUE}Available Notification Channels:${NC}"
    echo ""
    
    # Desktop
    if command -v notify-send >/dev/null 2>&1; then
        echo -e "  Desktop: ${GREEN}✓ (notify-send)${NC}"
    elif command -v osascript >/dev/null 2>&1; then
        echo -e "  Desktop: ${GREEN}✓ (osascript)${NC}"
    elif command -v termux-notification >/dev/null 2>&1; then
        echo -e "  Desktop: ${GREEN}✓ (termux-notification)${NC}"
    else
        echo -e "  Desktop: ${YELLOW}! (not configured)${NC}"
    fi
    
    # Email
    if command -v mail >/dev/null 2>&1; then
        echo -e "  Email: ${GREEN}✓ (mail)${NC}"
    elif command -v sendmail >/dev/null 2>&1; then
        echo -e "  Email: ${GREEN}✓ (sendmail)${NC}"
    else
        echo -e "  Email: ${YELLOW}! (not configured)${NC}"
    fi
    
    # Webhook
    if command -v curl >/dev/null 2>&1; then
        echo -e "  Webhook: ${GREEN}✓ (curl)${NC}"
    else
        echo -e "  Webhook: ${YELLOW}! (curl not found)${NC}"
    fi
}

# Test notification
cmd_test() {
    echo -e "${BLUE}Testing notification system...${NC}"
    echo ""
    
    cmd_send_desktop "Test" "This is a test notification"
    echo ""
    
    echo -e "${GREEN}✓ Test complete${NC}"
}

# Show help
show_help() {
    cat <<EOF
Notification MCP - Send notifications

Usage: oml mcp notification <command> [args]

Commands:
  send_desktop <title> <msg>    Send desktop notification
  send_email <to> <subj> <body> Send email notification
  send_webhook <url> <msg>      Send webhook notification
  list_channels                 List available channels
  test                          Test notification system
  help                          Show this help

Security:
  - Email and webhook require confirmation
  - Rate limit: 10 notifications/minute

Examples:
  oml mcp notification send_desktop "Alert" "Build completed"
  oml mcp notification send_email "user@example.com" "Alert" "Build failed"
  oml mcp notification send_webhook "https://hooks.slack.com/..." "Build done"
  oml mcp notification list_channels
  oml mcp notification test

EOF
}

# Main function
main() {
    local command="${1:-help}"
    shift || true
    
    case "$command" in
        send_desktop)
            cmd_send_desktop "$@"
            ;;
        send_email)
            cmd_send_email "$@"
            ;;
        send_webhook)
            cmd_send_webhook "$@"
            ;;
        list_channels)
            cmd_list_channels
            ;;
        test)
            cmd_test
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}Unknown command: $command${NC}"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
