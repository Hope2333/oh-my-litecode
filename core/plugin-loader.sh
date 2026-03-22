#!/usr/bin/env bash
# OML Plugin Loader
# Loads and manages plugins (agents, subagents, MCPs, skills)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Try to find OML root
if [[ -z "${OML_ROOT:-}" ]]; then
    if [[ "$(basename "$SCRIPT_DIR")" == "core" ]]; then
        export OML_ROOT="$(dirname "$SCRIPT_DIR")"
    fi
fi

# Source platform if available
if [[ -z "${OML_PLATFORM_LOADED:-}" && -f "${SCRIPT_DIR}/platform.sh" ]]; then
    source "${SCRIPT_DIR}/platform.sh"
    export OML_PLATFORM_LOADED=true
fi

# Plugin directories (resolved dynamically)
OML_PLUGINS_ROOT="${OML_PLUGINS_ROOT:-${OML_ROOT:-}/plugins}"

# Get plugin type directory
oml_plugin_type_dir() {
    local type="$1"
    local base_dir="${OML_PLUGINS_ROOT:-}"
    
    # If OML_PLUGINS_ROOT not set, try to find it
    if [[ -z "$base_dir" ]]; then
        if [[ -n "${OML_ROOT:-}" ]]; then
            base_dir="${OML_ROOT}/plugins"
        elif [[ -f "${HOME}/.oml/config.json" ]]; then
            base_dir="$(python3 -c "import json; print(json.load(open('${HOME}/.oml/config.json')).get('pluginsDir', ''))" 2>/dev/null || true)"
        fi
    fi
    
    if [[ -z "$base_dir" ]]; then
        return 1
    fi
    
    case "$type" in
        agent|agents) echo "${base_dir}/agents" ;;
        subagent|subagents) echo "${base_dir}/subagents" ;;
        mcp|mcps) echo "${base_dir}/mcps" ;;
        skill|skills) echo "${base_dir}/skills" ;;
        *) echo "" ;;
    esac
}

# Find plugin directory by name and type
oml_find_plugin() {
    local name="$1"
    local type="${2:-}"
    
    if [[ -n "$type" ]]; then
        local plugin_dir
        plugin_dir="$(oml_plugin_type_dir "$type")"
        if [[ -d "${plugin_dir}/${name}" ]]; then
            echo "${plugin_dir}/${name}"
            return 0
        fi
    else
        # Search all plugin types
        for plugin_type in agents subagents mcps skills; do
            local plugin_dir
            plugin_dir="$(oml_plugin_type_dir "$plugin_type")"
            if [[ -d "${plugin_dir}/${name}" ]]; then
                echo "${plugin_dir}/${name}"
                return 0
            fi
        done
    fi
    
    return 1
}

# Read plugin metadata
oml_plugin_meta() {
    local plugin_dir="$1"
    local field="${2:-}"
    
    local meta_file="${plugin_dir}/plugin.json"
    if [[ ! -f "$meta_file" ]]; then
        return 1
    fi
    
    if [[ -z "$field" ]]; then
        cat "$meta_file"
    else
        python3 -c "
import json
with open('${meta_file}', 'r') as f:
    data = json.load(f)
print(data.get('${field}', ''))
"
    fi
}

# List available plugins
oml_plugins_list() {
    local type="${1:-all}"
    local format="${2:-plain}"
    
    local plugins=()
    
    if [[ "$type" == "all" ]]; then
        for plugin_type in agents subagents mcps skills; do
            local plugin_dir
            plugin_dir="$(oml_plugin_type_dir "$plugin_type")"
            if [[ -d "$plugin_dir" ]]; then
                for plugin in "$plugin_dir"/*/; do
                    if [[ -d "$plugin" ]]; then
                        local name
                        name="$(basename "$plugin")"
                        local version
                        version="$(oml_plugin_meta "$plugin" version 2>/dev/null || echo "unknown")"
                        plugins+=("${plugin_type}/${name}:${version}")
                    fi
                done
            fi
        done
    else
        local plugin_dir
        plugin_dir="$(oml_plugin_type_dir "$type")"
        if [[ -d "$plugin_dir" ]]; then
            for plugin in "$plugin_dir"/*/; do
                if [[ -d "$plugin" ]]; then
                    local name
                    name="$(basename "$plugin")"
                    local version
                    version="$(oml_plugin_meta "$plugin" version 2>/dev/null || echo "unknown")"
                    plugins+=("${name}:${version}")
                fi
            done
        fi
    fi
    
    case "$format" in
        json)
            printf '['
            local first=true
            for plugin in "${plugins[@]}"; do
                if [[ "$first" == true ]]; then
                    first=false
                else
                    printf ','
                fi
                printf '"%s"' "$plugin"
            done
            printf ']\n'
            ;;
        plain)
            for plugin in "${plugins[@]}"; do
                echo "$plugin"
            done
            ;;
        *)
            for plugin in "${plugins[@]}"; do
                echo "$plugin"
            done
            ;;
    esac
}

# Install plugin from directory or URL
oml_plugin_install() {
    local source="$1"
    local type="${2:-agent}"
    local name="${3:-}"
    
    local plugin_dir
    plugin_dir="$(oml_plugin_type_dir "$type")"
    
    if [[ -z "$plugin_dir" ]]; then
        echo "Error: Invalid plugin type: $type" >&2
        return 1
    fi
    
    # If source is a directory, copy it
    if [[ -d "$source" ]]; then
        if [[ -z "$name" ]]; then
            name="$(basename "$source")"
        fi
        cp -r "$source" "${plugin_dir}/${name}"
        echo "Installed plugin: ${type}/${name}"
        return 0
    fi
    
    # If source is a git URL, clone it
    if [[ "$source" =~ ^https?:// ]] || [[ "$source" =~ ^git@ ]]; then
        local temp_dir
        temp_dir="$(mktemp -d)"
        git clone "$source" "$temp_dir"
        
        if [[ -z "$name" ]]; then
            name="$(basename "$source" .git)"
        fi
        
        # Find plugin directory in cloned repo
        local found_plugin=""
        for subdir in agents subagents mcps skills; do
            if [[ -d "${temp_dir}/${subdir}" ]]; then
                for plugin in "${temp_dir}/${subdir}"/*/; do
                    if [[ -d "$plugin" ]]; then
                        found_plugin="$plugin"
                        type="$subdir"
                        plugin_dir="$(oml_plugin_type_dir "$type")"
                        break
                    fi
                done
            fi
        done
        
        if [[ -n "$found_plugin" ]]; then
            name="$(basename "$found_plugin")"
            cp -r "$found_plugin" "${plugin_dir}/${name}"
            echo "Installed plugin: ${type}/${name}"
            rm -rf "$temp_dir"
            return 0
        else
            echo "Error: No plugin found in repository" >&2
            rm -rf "$temp_dir"
            return 1
        fi
    fi
    
    echo "Error: Invalid plugin source: $source" >&2
    return 1
}

# Enable plugin (create symlink in config)
oml_plugin_enable() {
    local name="$1"
    local type="${2:-}"
    
    local plugin_dir
    plugin_dir="$(oml_find_plugin "$name" "$type")"
    
    if [[ -z "$plugin_dir" ]]; then
        echo "Error: Plugin not found: $name" >&2
        return 1
    fi
    
    # Extract type from plugin_dir
    type="$(echo "$plugin_dir" | sed "s|${OML_PLUGINS_ROOT}/||" | cut -d'/' -f1)"
    
    local config_dir
    config_dir="$(oml_config_dir)"
    local enabled_dir="${config_dir}/enabled/${type}"
    mkdir -p "$enabled_dir"
    
    ln -sf "$plugin_dir" "${enabled_dir}/${name}"
    echo "Enabled plugin: ${type}/${name}"
}

# Disable plugin
oml_plugin_disable() {
    local name="$1"
    local type="${2:-}"
    
    local config_dir
    config_dir="$(oml_config_dir)"
    local enabled_file="${config_dir}/enabled/${type}/${name}"
    
    if [[ -L "$enabled_file" ]]; then
        rm "$enabled_file"
        echo "Disabled plugin: ${type}/${name}"
    else
        echo "Plugin not enabled: ${type}/${name}"
    fi
}

# Run plugin command
oml_plugin_run() {
    local name="$1"
    local command="${2:-}"
    shift 2 || true
    
    local plugin_dir
    plugin_dir="$(oml_find_plugin "$name")"
    
    if [[ -z "$plugin_dir" ]]; then
        echo "Error: Plugin not found: $name" >&2
        return 1
    fi
    
    local main_script="${plugin_dir}/main.sh"
    if [[ ! -x "$main_script" ]]; then
        echo "Error: Plugin main.sh not found or not executable" >&2
        return 1
    fi
    
    # Load plugin environment
    local config_dir
    config_dir="$(oml_config_dir)"
    
    # Run plugin command
    if [[ -n "$command" ]]; then
        "$main_script" "$command" "$@"
    else
        "$main_script" "$@"
    fi
}

# Get plugin info
oml_plugin_info() {
    local name="$1"
    
    local plugin_dir
    plugin_dir="$(oml_find_plugin "$name")"
    
    if [[ -z "$plugin_dir" ]]; then
        echo "Error: Plugin not found: $name" >&2
        return 1
    fi
    
    echo "Plugin: $name"
    echo "Directory: $plugin_dir"
    echo ""
    echo "Metadata:"
    oml_plugin_meta "$plugin_dir" | python3 -c "
import json
import sys
data = json.load(sys.stdin)
for key, value in data.items():
    print(f'  {key}: {value}')
" 2>/dev/null || echo "  (no metadata)"
    echo ""
    echo "Files:"
    ls -la "$plugin_dir" 2>/dev/null | tail -n +2 | sed 's/^/  /'
}

# Create plugin template
oml_plugin_create() {
    local name="$1"
    local type="${2:-agent}"
    
    local plugin_dir
    plugin_dir="$(oml_plugin_type_dir "$type")"
    
    if [[ -z "$plugin_dir" ]]; then
        echo "Error: Invalid plugin type: $type" >&2
        return 1
    fi
    
    local new_plugin="${plugin_dir}/${name}"
    if [[ -d "$new_plugin" ]]; then
        echo "Error: Plugin already exists: $name" >&2
        return 1
    fi
    
    mkdir -p "$new_plugin"
    mkdir -p "$new_plugin/scripts"
    
    # Create plugin.json
    cat > "${new_plugin}/plugin.json" <<EOF
{
  "name": "${name}",
  "version": "0.1.0",
  "type": "${type}",
  "description": "${name} plugin for OML",
  "author": "Your Name",
  "license": "MIT",
  "platforms": ["termux", "gnu-linux"],
  "dependencies": [],
  "env": {},
  "commands": [
    {
      "name": "default",
      "description": "Default command",
      "handler": "main.sh"
    }
  ],
  "hooks": {
    "post_install": "scripts/post-install.sh",
    "pre_uninstall": "scripts/pre-uninstall.sh"
  }
}
EOF
    
    # Create main.sh
    cat > "${new_plugin}/main.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

main() {
    local action="${1:-help}"
    shift || true
    
    case "$action" in
        help|--help|-h)
            echo "Usage: oml ${PLUGIN_NAME:-plugin} <command> [args]"
            echo ""
            echo "Commands:"
            echo "  run    Execute main function"
            echo "  help   Show this help"
            ;;
        run)
            echo "Plugin ${PLUGIN_NAME:-plugin} is running..."
            # Add your logic here
            ;;
        *)
            echo "Unknown command: $action"
            return 1
            ;;
    esac
}

main "$@"
EOF
    chmod +x "${new_plugin}/main.sh"
    
    # Create post-install.sh
    cat > "${new_plugin}/scripts/post-install.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "Post-install hook for plugin"
# Add post-install logic here
EOF
    chmod +x "${new_plugin}/scripts/post-install.sh"
    
    # Create pre-uninstall.sh
    cat > "${new_plugin}/scripts/pre-uninstall.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "Pre-uninstall hook for plugin"
# Add pre-uninstall logic here
EOF
    chmod +x "${new_plugin}/scripts/pre-uninstall.sh"
    
    echo "Created plugin template: ${type}/${name}"
    echo "Edit ${new_plugin}/plugin.json to customize"
}

# Main CLI entry
main() {
    local action="${1:-help}"
    shift || true
    
    case "$action" in
        list)
            oml_plugins_list "$@"
            ;;
        install)
            oml_plugin_install "$@"
            ;;
        enable)
            oml_plugin_enable "$@"
            ;;
        disable)
            oml_plugin_disable "$@"
            ;;
        run)
            oml_plugin_run "$@"
            ;;
        info)
            oml_plugin_info "$@"
            ;;
        create)
            oml_plugin_create "$@"
            ;;
        help|--help|-h)
            cat <<EOF
OML Plugin Loader

Usage: oml plugins <action> [args]

Actions:
  list [type] [format]     List plugins (type: all|agents|subagents|mcps|skills)
  install <source> [type]  Install plugin from directory or git URL
  enable <name> [type]     Enable a plugin
  disable <name> [type]    Disable a plugin
  run <name> [cmd] [args]  Run plugin command
  info <name>              Show plugin information
  create <name> [type]     Create new plugin template

Examples:
  oml plugins list
  oml plugins list agents json
  oml plugins install ./my-plugin agent
  oml plugins enable qwen
  oml plugins run qwen chat "Hello"
  oml plugins create my-agent agent
EOF
            ;;
        *)
            echo "Unknown action: $action"
            echo "Use 'oml plugins help' for usage"
            return 1
            ;;
    esac
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
