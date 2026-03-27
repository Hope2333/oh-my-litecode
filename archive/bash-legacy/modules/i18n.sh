#!/usr/bin/env bash
# OML i18n - Multi-language support
#
# Usage:
#   oml i18n set <lang>
#   oml i18n list
#   oml i18n translate <key>

set -euo pipefail

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# Configuration
I18N_DIR="${HOME}/.oml/i18n"
CURRENT_LANG="${I18N_DIR}/current.lang"
SUPPORTED_LANGS=("en" "zh-CN" "zh-TW" "ja" "ko")

print_step() { echo -e "${BLUE}==>${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1" >&2; }

# Initialize i18n
init_i18n() {
    mkdir -p "$I18N_DIR"
    
    # Create language files if not exist
    for lang in "${SUPPORTED_LANGS[@]}"; do
        local lang_file="${I18N_DIR}/${lang}.json"
        if [[ ! -f "$lang_file" ]]; then
            case "$lang" in
                en)
                    cat > "$lang_file" <<EOF
{
  "welcome": "Welcome to OML",
  "installing": "Installing...",
  "complete": "Complete",
  "error": "Error",
  "help": "Help"
}
EOF
                    ;;
                zh-CN)
                    cat > "$lang_file" <<EOF
{
  "welcome": "欢迎使用 OML",
  "installing": "正在安装...",
  "complete": "完成",
  "error": "错误",
  "help": "帮助"
}
EOF
                    ;;
                zh-TW)
                    cat > "$lang_file" <<EOF
{
  "welcome": "歡迎使用 OML",
  "installing": "正在安裝...",
  "complete": "完成",
  "error": "錯誤",
  "help": "幫助"
}
EOF
                    ;;
                ja)
                    cat > "$lang_file" <<EOF
{
  "welcome": "OML へようこそ",
  "installing": "インストール中...",
  "complete": "完了",
  "error": "エラー",
  "help": "ヘルプ"
}
EOF
                    ;;
                ko)
                    cat > "$lang_file" <<EOF
{
  "welcome": "OML 에 오신 것을 환영합니다",
  "installing": "설치 중...",
  "complete": "완료",
  "error": "오류",
  "help": "도움말"
}
EOF
                    ;;
            esac
        fi
    done
}

# Set language
cmd_set() {
    local lang="${1:-}"
    
    if [[ -z "$lang" ]]; then
        print_error "Language required"
        echo "Supported: ${SUPPORTED_LANGS[*]}"
        return 1
    fi
    
    # Check if language is supported
    local supported=false
    for supported_lang in "${SUPPORTED_LANGS[@]}"; do
        if [[ "$lang" == "$supported_lang" ]]; then
            supported=true
            break
        fi
    done
    
    if [[ "$supported" == false ]]; then
        print_error "Unsupported language: $lang"
        echo "Supported: ${SUPPORTED_LANGS[*]}"
        return 1
    fi
    
    init_i18n
    echo "$lang" > "$CURRENT_LANG"
    print_success "Language set to: $lang"
}

# List available languages
cmd_list() {
    init_i18n
    
    echo -e "${BLUE}Available Languages:${NC}"
    echo ""
    
    local current=""
    if [[ -f "$CURRENT_LANG" ]]; then
        current=$(cat "$CURRENT_LANG")
    fi
    
    for lang in "${SUPPORTED_LANGS[@]}"; do
        local marker="  "
        if [[ "$lang" == "$current" ]]; then
            marker="* "
        fi
        
        local lang_name
        case "$lang" in
            en) lang_name="English" ;;
            zh-CN) lang_name="简体中文" ;;
            zh-TW) lang_name="繁體中文" ;;
            ja) lang_name="日本語" ;;
            ko) lang_name="한국어" ;;
            *) lang_name="$lang" ;;
        esac
        
        echo -e "${marker}${GREEN}${lang}${NC} - ${lang_name}"
    done
    
    echo ""
    echo "Use 'oml i18n set <lang>' to switch language"
}

# Translate key
cmd_translate() {
    local key="${1:-}"
    
    if [[ -z "$key" ]]; then
        print_error "Key required"
        return 1
    fi
    
    init_i18n
    
    local lang="en"
    if [[ -f "$CURRENT_LANG" ]]; then
        lang=$(cat "$CURRENT_LANG")
    fi
    
    local lang_file="${I18N_DIR}/${lang}.json"
    local translation
    translation=$(jq -r --arg k "$key" '.[$k] // $k' "$lang_file" 2>/dev/null)
    
    echo "$translation"
}

# Show help
show_help() {
    cat <<EOF
OML i18n - Multi-language support

Usage: oml i18n <command>

Commands:
  set <lang>          Set current language
  list                List available languages
  translate <key>     Translate a key
  help                Show this help

Supported Languages:
  en      - English
  zh-CN   - 简体中文
  zh-TW   - 繁體中文
  ja      - 日本語
  ko      - 한국어

Examples:
  oml i18n set zh-CN
  oml i18n list
  oml i18n translate welcome

EOF
}

# Main
main() {
    local cmd="${1:-help}"; shift || true
    case "$cmd" in
        set) cmd_set "$@" ;; list) cmd_list ;; translate) cmd_translate "$@" ;;
        help|--help|-h) show_help ;; *) print_error "Unknown: $cmd"; show_help; exit 1 ;;
    esac
}

main "$@"
