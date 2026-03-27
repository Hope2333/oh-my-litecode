#!/usr/bin/env bash
# Scout Plugin - File Type Statistics

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# Generate file type statistics
scout_file_stats() {
    local root_dir="${1:-.}"
    local exclude_patterns="${2:-$(scout_get_default_excludes)}"
    local output_format="${3:-json}"
    
    root_dir=$(scout_validate_dir "$root_dir")
    
    local find_args
    find_args=$(scout_parse_excludes "$exclude_patterns")
    
    case "$output_format" in
        json)
            _scout_stats_json "$root_dir" "$find_args"
            ;;
        markdown)
            _scout_stats_markdown "$root_dir" "$find_args"
            ;;
        text|*)
            _scout_stats_text "$root_dir" "$find_args"
            ;;
    esac
}

# Internal: Stats in JSON format
_scout_stats_json() {
    local root_dir="$1"
    local find_args="$2"
    
    python3 - "$root_dir" "$find_args" <<'PYTHON'
import os
import sys
import json
from collections import defaultdict

root_dir = sys.argv[1]
find_args = sys.argv[2]

# Parse find args to get exclude patterns
exclude_patterns = []
parts = find_args.split()
for i, part in enumerate(parts):
    if part == "-name" and i + 1 < len(parts):
        exclude_patterns.append(parts[i + 1].strip("'"))

stats = {
    'by_extension': defaultdict(lambda: {'count': 0, 'size': 0, 'lines': 0}),
    'by_language': defaultdict(lambda: {'count': 0, 'size': 0, 'lines': 0}),
    'total': {'files': 0, 'directories': 0, 'size': 0, 'lines': 0},
    'largest_files': [],
    'most_lines': []
}

ext_to_lang = {
    'js': 'javascript', 'mjs': 'javascript', 'cjs': 'javascript',
    'ts': 'typescript', 'tsx': 'typescript',
    'py': 'python', 'pyw': 'python',
    'sh': 'bash', 'bash': 'bash',
    'go': 'go',
    'rs': 'rust',
    'java': 'java',
    'c': 'c', 'h': 'c',
    'cpp': 'cpp', 'cc': 'cpp', 'cxx': 'cpp', 'hpp': 'cpp',
    'rb': 'ruby',
    'php': 'php',
    'pl': 'perl', 'pm': 'perl',
    'hs': 'haskell',
    'ex': 'elixir', 'exs': 'elixir',
    'clj': 'clojure', 'cljs': 'clojure',
    'erl': 'erlang',
    'ml': 'ocaml',
    'swift': 'swift',
    'kt': 'kotlin', 'kts': 'kotlin',
    'scala': 'scala',
    'r': 'r', 'R': 'r',
    'lua': 'lua',
    'sql': 'sql',
    'html': 'html', 'htm': 'html',
    'css': 'css', 'scss': 'css', 'sass': 'css', 'less': 'css',
    'json': 'json',
    'xml': 'xml',
    'yaml': 'yaml', 'yml': 'yaml',
    'md': 'markdown', 'markdown': 'markdown',
    'txt': 'text',
    'dockerfile': 'dockerfile',
    'makefile': 'makefile',
    'toml': 'toml',
    'ini': 'ini',
    'cfg': 'config',
    'conf': 'config',
}

def should_exclude(path, exclude_patterns):
    parts = path.split(os.sep)
    for part in parts:
        if part in exclude_patterns:
            return True
    return False

def count_lines(filepath):
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            return sum(1 for _ in f)
    except:
        return 0

for dirpath, dirnames, filenames in os.walk(root_dir):
    # Filter excluded directories
    dirnames[:] = [d for d in dirnames if not should_exclude(os.path.join(dirpath, d), exclude_patterns)]
    stats['total']['directories'] += 1
    
    for filename in filenames:
        if should_exclude(filename, exclude_patterns):
            continue
        
        filepath = os.path.join(dirpath, filename)
        
        try:
            size = os.path.getsize(filepath)
            lines = count_lines(filepath)
        except:
            size = 0
            lines = 0
        
        ext = os.path.splitext(filename)[1].lstrip('.').lower()
        if not ext:
            ext = os.path.basename(filename).lower()
            if ext in ['dockerfile', 'makefile']:
                pass
            else:
                ext = ''
        
        language = ext_to_lang.get(ext, 'other')
        
        # Update stats
        stats['by_extension'][ext]['count'] += 1
        stats['by_extension'][ext]['size'] += size
        stats['by_extension'][ext]['lines'] += lines
        
        stats['by_language'][language]['count'] += 1
        stats['by_language'][language]['size'] += size
        stats['by_language'][language]['lines'] += lines
        
        stats['total']['files'] += 1
        stats['total']['size'] += size
        stats['total']['lines'] += lines
        
        # Track largest files
        stats['largest_files'].append({'path': filepath, 'size': size, 'ext': ext})
        stats['most_lines'].append({'path': filepath, 'lines': lines, 'ext': ext})

# Sort and limit
stats['largest_files'] = sorted(stats['largest_files'], key=lambda x: x['size'], reverse=True)[:10]
stats['most_lines'] = sorted(stats['most_lines'], key=lambda x: x['lines'], reverse=True)[:10]

# Convert defaultdicts to regular dicts for JSON
stats['by_extension'] = dict(stats['by_extension'])
stats['by_language'] = dict(stats['by_language'])

# Format for output
output = {
    'summary': stats['total'],
    'by_extension': {k: v for k, v in sorted(stats['by_extension'].items(), key=lambda x: x[1]['count'], reverse=True)},
    'by_language': {k: v for k, v in sorted(stats['by_language'].items(), key=lambda x: x[1]['count'], reverse=True)},
    'top_files_by_size': stats['largest_files'],
    'top_files_by_lines': stats['most_lines']
}

print(json.dumps(output, indent=2))
PYTHON
}

# Internal: Stats in Markdown format
_scout_stats_markdown() {
    local root_dir="$1"
    local find_args="$2"
    
    local stats
    stats=$(_scout_stats_json "$root_dir" "$find_args")
    
    echo "# File Statistics Report"
    echo ""
    echo "**Directory:** $root_dir"
    echo "**Generated at:** $(scout_timestamp)"
    echo ""
    
    echo "## Summary"
    echo ""
    echo "$stats" | python3 -c "
import sys, json
data = json.load(sys.stdin)['summary']
print(f\"- **Total Files:** {data['files']}\")
print(f\"- **Total Directories:** {data['directories']}\")
print(f\"- **Total Size:** {data['size']:,} bytes\")
print(f\"- **Total Lines:** {data['lines']:,}\")
"
    echo ""
    
    echo "## By Language"
    echo ""
    echo "| Language | Files | Size | Lines |"
    echo "|----------|-------|------|-------|"
    echo "$stats" | python3 -c "
import sys, json
data = json.load(sys.stdin)['by_language']
for lang, stats in list(data.items())[:15]:
    print(f'| {lang} | {stats[\"count\"]} | {stats[\"size\"]:,} | {stats[\"lines\"]:,} |')
if len(data) > 15:
    print(f'| ... | {len(data) - 15} more languages | | |')
"
    echo ""
    
    echo "## By Extension"
    echo ""
    echo "| Extension | Files | Size | Lines |"
    echo "|-----------|-------|------|-------|"
    echo "$stats" | python3 -c "
import sys, json
data = json.load(sys.stdin)['by_extension']
for ext, stats in list(data.items())[:15]:
    ext_display = ext if ext else '(no extension)'
    print(f'| {ext_display} | {stats[\"count\"]} | {stats[\"size\"]:,} | {stats[\"lines\"]:,} |')
if len(data) > 15:
    print(f'| ... | {len(data) - 15} more extensions | | |')
"
    echo ""
    
    echo "## Largest Files"
    echo ""
    echo "| File | Size |"
    echo "|------|------|"
    echo "$stats" | python3 -c "
import sys, json
data = json.load(sys.stdin)['top_files_by_size']
for f in data:
    print(f'| {f[\"path\"]} | {f[\"size\"]:,} bytes |')
"
    echo ""
    
    echo "## Files with Most Lines"
    echo ""
    echo "| File | Lines |"
    echo "|------|-------|"
    echo "$stats" | python3 -c "
import sys, json
data = json.load(sys.stdin)['top_files_by_lines']
for f in data:
    print(f'| {f[\"path\"]} | {f[\"lines\"]:,} |')
"
}

# Internal: Stats in text format
_scout_stats_text() {
    local root_dir="$1"
    local find_args="$2"
    
    local stats
    stats=$(_scout_stats_json "$root_dir" "$find_args")
    
    echo "File Statistics Report"
    echo "======================"
    echo ""
    echo "Directory: $root_dir"
    echo "Generated: $(scout_timestamp)"
    echo ""
    echo "Summary"
    echo "-------"
    echo "$stats" | python3 -c "
import sys, json
data = json.load(sys.stdin)['summary']
print(f\"Total Files:      {data['files']}\")
print(f\"Total Directories: {data['directories']}\")
print(f\"Total Size:       {data['size']:,} bytes\")
print(f\"Total Lines:      {data['lines']:,}\")
"
    echo ""
    echo "By Language (Top 10)"
    echo "--------------------"
    echo "$stats" | python3 -c "
import sys, json
data = json.load(sys.stdin)['by_language']
for lang, stats in list(data.items())[:10]:
    print(f'{lang:20} {stats[\"count\"]:5} files  {stats[\"size\"]:12,} bytes  {stats[\"lines\"]:8,} lines')
"
    echo ""
    echo "By Extension (Top 10)"
    echo "---------------------"
    echo "$stats" | python3 -c "
import sys, json
data = json.load(sys.stdin)['by_extension']
for ext, stats in list(data.items())[:10]:
    ext_display = ext if ext else '(no ext)'
    print(f'.{ext_display:15} {stats[\"count\"]:5} files  {stats[\"size\"]:12,} bytes  {stats[\"lines\"]:8,} lines')
"
}

# Quick stats summary
scout_quick_stats() {
    local root_dir="${1:-.}"
    
    root_dir=$(scout_validate_dir "$root_dir")
    
    local file_count dir_count total_size
    file_count=$(find "$root_dir" -type f 2>/dev/null | wc -l | tr -d ' ')
    dir_count=$(find "$root_dir" -type d 2>/dev/null | wc -l | tr -d ' ')
    total_size=$(du -sh "$root_dir" 2>/dev/null | cut -f1 || echo "unknown")
    
    local code_files
    code_files=$(find "$root_dir" -type f \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.go" -o -name "*.rs" -o -name "*.java" -o -name "*.c" -o -name "*.cpp" \) 2>/dev/null | wc -l | tr -d ' ')
    
    echo "Quick Stats for: $root_dir"
    echo "  Files:       $file_count"
    echo "  Directories: $dir_count"
    echo "  Size:        $total_size"
    echo "  Code Files:  $code_files"
}
