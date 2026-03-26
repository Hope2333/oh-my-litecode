#!/usr/bin/env bash
# Fakehome Nesting Detection and Fix Module
# Only fixes NESTED fakehomes, not single-level fakehomes

# Fix nested fakehome (e.g., /home/user/.local/home/qwenx/.local/home/qwen)
# Does NOT fix single-level fakehome (e.g., /home/user/.local/home/qwenx)
_fix_fakehome_nesting() {
    # Check if HOME contains nested .local/home pattern
    # Pattern: /.local/home/XXX/.local/home/
    if [[ "${HOME}" == *"/.local/home/"*"/.local/home/"* ]]; then
        # This is a nested fakehome, extract the outer one
        local real_home
        real_home=$(echo "$HOME" | sed 's|/\.local/home/[^/]*$||')
        
        if [[ -d "$real_home" && "$real_home" != "$HOME" ]]; then
            export _FAKEHOME_ORIGINAL="${HOME}"
            export HOME="${real_home}"
            export _FAKEHOME_FIXED="true"
            export _FAKEHOME_NESTING_DETECTED="true"
        fi
    fi
}

# Auto-apply fix when sourced
_fix_fakehome_nesting
