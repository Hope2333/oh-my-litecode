#!/usr/bin/env bash
# Database MCP - Database operations (placeholder)
#
# Note: Full implementation requires database drivers
# This is a placeholder supporting SQLite

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Database connection
DB_FILE=""
DB_CONNECTED=false

# Connect to database
cmd_connect() {
    local db_file="${1:-:memory:}"
    
    DB_FILE="$db_file"
    DB_CONNECTED=true
    
    echo -e "${GREEN}✓ Connected to: $db_file${NC}"
    echo "Type: SQLite"
    echo "Mode: $( [[ "$db_file" == ":memory:" ]] && echo "In-memory" || echo "File" )"
}

# Execute SQL query
cmd_query() {
    local sql="${1:-}"
    
    if [[ "$DB_CONNECTED" != "true" ]]; then
        echo -e "${RED}Error: Not connected to database${NC}" >&2
        echo "Run 'oml mcp database connect' first" >&2
        return 1
    fi
    
    if [[ -z "$sql" ]]; then
        echo -e "${RED}Error: SQL query required${NC}" >&2
        return 1
    fi
    
    # Safety check
    if [[ "$sql" =~ (DROP|TRUNCATE) ]]; then
        echo -e "${RED}Error: Dangerous operation blocked${NC}" >&2
        return 1
    fi
    
    echo -e "${BLUE}Executing: $sql${NC}"
    
    if command -v sqlite3 >/dev/null 2>&1; then
        if [[ "$DB_FILE" == ":memory:" ]]; then
            echo "Result: (in-memory database)"
            echo "$sql" | sqlite3 :memory:
        else
            echo "$sql" | sqlite3 "$DB_FILE"
        fi
    else
        echo -e "${YELLOW}Warning: sqlite3 not installed, showing placeholder${NC}"
        echo "Result: (placeholder - install sqlite3 for full functionality)"
    fi
}

# Insert data
cmd_insert() {
    local table="${1:-}"
    local data="${2:-}"
    
    if [[ -z "$table" ]] || [[ -z "$data" ]]; then
        echo -e "${RED}Error: Table and data required${NC}" >&2
        return 1
    fi
    
    local sql="INSERT INTO $table VALUES ($data)"
    echo -e "${YELLOW}Confirm insert? (y/N)${NC}"
    read -r confirm
    
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        cmd_query "$sql"
    else
        echo "Cancelled"
    fi
}

# Update data
cmd_update() {
    local table="${1:-}"
    local set_clause="${2:-}"
    local where_clause="${3:-}"
    
    if [[ -z "$table" ]] || [[ -z "$set_clause" ]]; then
        echo -e "${RED}Error: Table and SET clause required${NC}" >&2
        return 1
    fi
    
    local sql="UPDATE $table SET $set_clause"
    if [[ -n "$where_clause" ]]; then
        sql="$sql WHERE $where_clause"
    fi
    
    echo -e "${YELLOW}Confirm update? (y/N)${NC}"
    read -r confirm
    
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        cmd_query "$sql"
    else
        echo "Cancelled"
    fi
}

# Delete data
cmd_delete() {
    local table="${1:-}"
    local where_clause="${2:-}"
    
    if [[ -z "$table" ]]; then
        echo -e "${RED}Error: Table required${NC}" >&2
        return 1
    fi
    
    if [[ -z "$where_clause" ]]; then
        echo -e "${RED}Error: WHERE clause required for safety${NC}" >&2
        return 1
    fi
    
    local sql="DELETE FROM $table WHERE $where_clause"
    echo -e "${RED}Confirm delete? THIS CANNOT BE UNDONE! (y/N)${NC}"
    read -r confirm
    
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        cmd_query "$sql"
    else
        echo "Cancelled"
    fi
}

# List tables
cmd_list_tables() {
    if [[ "$DB_CONNECTED" != "true" ]]; then
        echo -e "${RED}Error: Not connected to database${NC}" >&2
        return 1
    fi
    
    echo -e "${BLUE}Tables in database:${NC}"
    cmd_query "SELECT name FROM sqlite_master WHERE type='table';"
}

# Disconnect
cmd_disconnect() {
    DB_CONNECTED=false
    DB_FILE=""
    echo -e "${GREEN}✓ Disconnected${NC}"
}

# Show help
show_help() {
    cat <<EOF
Database MCP - Database operations (SQLite placeholder)

Usage: oml mcp database <command> [args]

Commands:
  connect [db_file]        Connect to database (default: :memory:)
  query <sql>              Execute SQL query
  insert <table> <data>    Insert data (requires confirm)
  update <table> <set> [where]  Update data (requires confirm)
  delete <table> <where>   Delete data (requires confirm + where)
  list_tables              List all tables
  disconnect               Disconnect from database
  help                     Show this help

Security:
  - Dangerous operations (DROP, TRUNCATE) are blocked
  - INSERT/UPDATE/DELETE require confirmation
  - DELETE requires WHERE clause

Examples:
  oml mcp database connect
  oml mcp database connect mydb.sqlite
  oml mcp database query "CREATE TABLE users (id INT, name TEXT)"
  oml mcp database query "SELECT * FROM users"
  oml mcp database insert users "1, 'John'"
  oml mcp database update users "name='Jane'" "id=1"
  oml mcp database list_tables
  oml mcp database disconnect

Note:
  Full implementation requires database drivers.
  Current implementation supports SQLite only.
  Install sqlite3 for full functionality.

EOF
}

# Main function
main() {
    local command="${1:-help}"
    shift || true
    
    case "$command" in
        connect)
            cmd_connect "$@"
            ;;
        query)
            cmd_query "$@"
            ;;
        insert)
            cmd_insert "$@"
            ;;
        update)
            cmd_update "$@"
            ;;
        delete)
            cmd_delete "$@"
            ;;
        list_tables)
            cmd_list_tables
            ;;
        disconnect)
            cmd_disconnect
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
