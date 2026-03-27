#!/usr/bin/env bash
# Scout Plugin - File Tree Generation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# Generate file tree structure
# Args: root_dir, max_depth, exclude_patterns, output_format
scout_generate_tree() {
    local root_dir="${1:-.}"
    local max_depth="${2:-5}"
    local exclude_patterns="${3:-$(scout_get_default_excludes)}"
    local output_format="${4:-text}"
    
    root_dir=$(scout_validate_dir "$root_dir")
    
    case "$output_format" in
        json)
            _scout_tree_json "$root_dir" "$max_depth" "$exclude_patterns"
            ;;
        markdown)
            _scout_tree_markdown "$root_dir" "$max_depth" "$exclude_patterns"
            ;;
        text|*)
            _scout_tree_text "$root_dir" "$max_depth" "$exclude_patterns"
            ;;
    esac
}

# Internal: Generate tree in text format
_scout_tree_text() {
    local root_dir="$1"
    local max_depth="$2"
    local exclude_patterns="$3"

    python3 - "$root_dir" "$max_depth" "$exclude_patterns" <<'PYTHON'
import os
import sys

root_dir = sys.argv[1]
max_depth = int(sys.argv[2])
exclude_patterns = [p.strip() for p in sys.argv[3].split(',') if p.strip()]

def build_tree_text(path, prefix="", depth=0):
    if depth > max_depth:
        return
    
    name = os.path.basename(path) or path
    if depth == 0:
        print(name + "/")
    
    try:
        entries = sorted(os.listdir(path))
    except PermissionError:
        return
    
    # Filter excluded
    entries = [e for e in entries if e not in exclude_patterns]
    
    dirs = [e for e in entries if os.path.isdir(os.path.join(path, e))]
    files = [e for e in entries if os.path.isfile(os.path.join(path, e))]
    
    # Print directories first, then files
    all_entries = [(d, True) for d in dirs] + [(f, False) for f in files]
    
    for i, (entry, is_dir) in enumerate(all_entries):
        is_last = (i == len(all_entries) - 1)
        connector = "└── " if is_last else "├── "
        
        if depth == 0:
            child_prefix = "    "
        else:
            child_prefix = "│   " if not is_last else "    "
        
        if is_dir:
            print(f"{prefix}{connector}📁 {entry}/")
            build_tree_text(os.path.join(path, entry), prefix + child_prefix, depth + 1)
        else:
            print(f"{prefix}{connector}📄 {entry}")

build_tree_text(root_dir)
PYTHON
}

# Internal: Generate tree in JSON format
_scout_tree_json() {
    local root_dir="$1"
    local max_depth="$2"
    local exclude_patterns="$3"
    
    python3 - "$root_dir" "$max_depth" "$exclude_patterns" <<'PYTHON'
import os
import sys
import json

def build_tree(path, max_depth, exclude_patterns, current_depth=0):
    if current_depth > max_depth:
        return None
    
    exclude_list = [p.strip() for p in exclude_patterns.split(',') if p.strip()]
    
    name = os.path.basename(path) or path
    result = {
        "name": name,
        "type": "directory" if os.path.isdir(path) else "file",
        "path": path
    }
    
    if os.path.isdir(path):
        # Check if should exclude
        if name in exclude_list:
            return None
        
        result["children"] = []
        try:
            entries = sorted(os.listdir(path))
            for entry in entries:
                if entry in exclude_list:
                    continue
                full_path = os.path.join(path, entry)
                child = build_tree(full_path, max_depth, exclude_patterns, current_depth + 1)
                if child:
                    result["children"].append(child)
        except PermissionError:
            pass
    else:
        # File info
        try:
            result["size"] = os.path.getsize(path)
            result["ext"] = os.path.splitext(name)[1].lstrip('.') or ""
        except:
            result["size"] = 0
            result["ext"] = ""
    
    return result

root_dir = sys.argv[1]
max_depth = int(sys.argv[2])
exclude_patterns = sys.argv[3] if len(sys.argv) > 3 else ""

tree = build_tree(root_dir, max_depth, exclude_patterns)
print(json.dumps(tree, indent=2))
PYTHON
}

# Internal: Generate tree in Markdown format
_scout_tree_markdown() {
    local root_dir="$1"
    local max_depth="$2"
    local exclude_patterns="$3"

    echo "## File Tree"
    echo ""
    echo '```'

    python3 - "$root_dir" "$max_depth" "$exclude_patterns" <<'PYTHON'
import os
import sys

root_dir = sys.argv[1]
max_depth = int(sys.argv[2])
exclude_patterns = [p.strip() for p in sys.argv[3].split(',') if p.strip()]

def build_tree_md(path, prefix="", depth=0):
    if depth > max_depth:
        return
    
    name = os.path.basename(path) or path
    if depth == 0:
        print(name + "/")
    
    try:
        entries = sorted(os.listdir(path))
    except PermissionError:
        return
    
    entries = [e for e in entries if e not in exclude_patterns]
    
    dirs = [e for e in entries if os.path.isdir(os.path.join(path, e))]
    files = [e for e in entries if os.path.isfile(os.path.join(path, e))]
    
    all_entries = [(d, True) for d in dirs] + [(f, False) for f in files]
    
    for i, (entry, is_dir) in enumerate(all_entries):
        is_last = (i == len(all_entries) - 1)
        connector = "└── " if is_last else "├── "
        
        if depth == 0:
            child_prefix = "    "
        else:
            child_prefix = "│   " if not is_last else "    "
        
        suffix = "/" if is_dir else ""
        print(f"{prefix}{connector}{entry}{suffix}")
        
        if is_dir:
            build_tree_md(os.path.join(path, entry), prefix + child_prefix, depth + 1)

build_tree_md(root_dir)
PYTHON

    echo '```'
}

# Count files and directories
scout_count_entries() {
    local root_dir="${1:-.}"
    local exclude_patterns="${2:-$(scout_get_default_excludes)}"
    
    root_dir=$(scout_validate_dir "$root_dir")
    
    local find_args
    find_args=$(scout_parse_excludes "$exclude_patterns")
    
    local file_count dir_count
    file_count=$(find "$root_dir" $find_args -type f 2>/dev/null | wc -l | tr -d ' ')
    dir_count=$(find "$root_dir" $find_args -type d 2>/dev/null | wc -l | tr -d ' ')
    
    echo "{\"files\": $file_count, \"directories\": $dir_count}"
}

# Get directory summary
scout_directory_summary() {
    local root_dir="${1:-.}"
    local exclude_patterns="${2:-$(scout_get_default_excludes)}"
    
    root_dir=$(scout_validate_dir "$root_dir")
    
    local counts
    counts=$(scout_count_entries "$root_dir" "$exclude_patterns")
    
    local total_size
    total_size=$(du -sb "$root_dir" 2>/dev/null | cut -f1 || echo "0")
    
    local human_size
    human_size=$(scout_human_size "$total_size")
    
    echo "Directory: $root_dir"
    echo "Total Size: $human_size ($total_size bytes)"
    echo "$counts" | python3 -c "
import sys, json
data = json.loads(sys.stdin.read())
print(f\"Files: {data['files']}\")
print(f\"Directories: {data['directories']}\")
"
}
