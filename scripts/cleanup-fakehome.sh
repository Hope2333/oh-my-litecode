#!/usr/bin/env bash
# Cleanup nested fakehome directories
# Merges data from nested fakehomes to the correct location

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step() { echo -e "${BLUE}==>${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}!${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1" >&2; }

# Base directories
QWENX_BASE="${HOME}/.local/home/qwenx"
QWEN_BASE="${HOME}/.local/home/qwen"

# Find and cleanup nested fakehomes
cleanup_nested() {
    local base_dir="$1"
    local nested_count=0
    
    print_step "Checking for nested fakehomes in $base_dir..."
    
    # Find nested .local/home directories
    while IFS= read -r nested_local; do
        if [[ -d "$nested_local" ]]; then
            nested_count=$((nested_count + 1))
            print_warning "Found nested: $nested_local"
            
            # Check for nested home directories
            for nested_home in "$nested_local"/home/*; do
                if [[ -d "$nested_home" ]]; then
                    local name=$(basename "$nested_home")
                    print_step "Processing nested home: $name"
                    
                    # Merge data if exists
                    for dir in .qwen .qwenx .cache .npm .oml; do
                        if [[ -d "$nested_home/$dir" ]]; then
                            local target="$base_dir/$dir"
                            if [[ -d "$target" ]]; then
                                print_step "Merging $nested_home/$dir -> $target"
                                cp -rv "$nested_home/$dir"/* "$target"/ 2>/dev/null || true
                            else
                                print_step "Moving $nested_home/$dir -> $target"
                                mv "$nested_home/$dir" "$target"
                            fi
                        fi
                    done
                    
                    # Remove nested after merge
                    rm -rf "$nested_home"
                    print_success "Removed nested: $name"
                fi
            done
            
            # Remove empty nested .local
            rmdir "$nested_local" 2>/dev/null || true
            rmdir "$(dirname "$nested_local")" 2>/dev/null || true
        fi
    done < <(find "$base_dir" -type d -name ".local" 2>/dev/null || true)
    
    if [[ $nested_count -eq 0 ]]; then
        print_success "No nested fakehomes found"
    else
        print_success "Cleaned $nested_count nested fakehome(s)"
    fi
}

# Main
main() {
    print_step "Starting fakehome cleanup..."
    
    cleanup_nested "$QWENX_BASE"
    cleanup_nested "$QWEN_BASE"
    
    print_success "Cleanup complete!"
}

main "$@"
