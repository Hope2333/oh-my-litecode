#!/usr/bin/env bash
# Fakehome Nesting Detection and Fix Module
# Automatically fixes HOME when inside nested fakehome

# Fix fakehome nesting
_fix_fakehome_home() {
    # Check if current HOME is inside a fakehome structure
    if [[ "${HOME}" == *"/.local/home/"* ]]; then
        # Extract the real home (parent of .local/home)
        local real_home
        real_home=$(echo "$HOME" | sed 's|/\.local/home/[^/]*$||')
        
        # Verify it's a valid home directory
        if [[ -d "$real_home" && "$real_home" != "$HOME" ]]; then
            export _FAKEHOME_ORIGINAL="${HOME}"
            export HOME="${real_home}"
            export _FAKEHOME_FIXED="true"
        fi
    fi
}

# Auto-apply fix when sourced
_fix_fakehome_home
