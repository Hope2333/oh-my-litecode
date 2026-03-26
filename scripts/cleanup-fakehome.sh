#!/usr/bin/env bash
# Cleanup nested fakehome directories
# ONLY cleans nested fakehomes, preserves single-level fakehomes

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

# Find and cleanup nested fakehomes
# Pattern: /.local/home/XXX/.local/home/
cleanup_nested() {
    local base_dir="$1"
    local cleaned=0
    
    print_step "Checking for nested fakehomes under $base_dir..."
    
    # Find nested .local/home directories
    while IFS= read -r nested_local; do
        if [[ -d "$nested_local" ]]; then
            local parent_dir=$(dirname "$nested_local")
            print_warning "Found nested structure: $nested_local"
            
            # Check for nested home directories
            for nested_home in "$nested_local"/home/*; do
                if [[ -d "$nested_home" ]]; then
                    local name=$(basename "$nested_home")
                    
                    # Skip if this is the current running environment
                    if [[ "$nested_home" == "$HOME" ]]; then
                        print_warning "Skipping current running environment: $nested_home"
                        continue
                    fi
                    
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
                    cleaned=$((cleaned + 1))
                    print_success "Removed nested: $name"
                fi
            done
            
            # Remove empty nested .local
            rmdir "$nested_local" 2>/dev/null || true
            rmdir "$parent_dir" 2>/dev/null || true
        fi
    done < <(find "$base_dir" -type d -path "*/.local/home/*/.local" 2>/dev/null || true)
    
    if [[ $cleaned -eq 0 ]]; then
        print_success "No nested fakehomes found"
    else
        print_success "Cleaned $cleaned nested fakehome(s)"
    fi
}

# Main
main() {
    print_step "Starting fakehome cleanup..."
    print_warning "Note: Only nested fakehomes will be cleaned"
    print_warning "Single-level fakehomes (like ~/.local/home/qwenx) are preserved"
    echo ""
    
    # Get real home
    local real_home="${HOME}"
    if [[ -n "${_FAKEHOME_ORIGINAL:-}" ]]; then
        real_home="${_FAKEHOME_ORIGINAL}"
    fi
    
    # Find base fakehome directories
    local fakehome_base=$(dirname "$real_home")
    
    if [[ -d "$fakehome_base" ]]; then
        cleanup_nested "$fakehome_base"
    fi
    
    print_success "Cleanup complete!"
}

main "$@"
