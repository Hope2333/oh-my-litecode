#!/usr/bin/env bash
# Scout Plugin - Dependency Analysis

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# Extract dependencies from a file
scout_extract_deps() {
    local file="$1"
    
    if [[ ! -f "$file" ]]; then
        scout_error "File not found: $file"
        return 1
    fi
    
    local lang
    lang=$(scout_detect_language "$file")
    
    case "$lang" in
        javascript|typescript)
            _scout_extract_js_deps "$file"
            ;;
        python)
            _scout_extract_python_deps "$file"
            ;;
        go)
            _scout_extract_go_deps "$file"
            ;;
        rust)
            _scout_extract_rust_deps "$file"
            ;;
        java)
            _scout_extract_java_deps "$file"
            ;;
        cpp|c)
            _scout_extract_c_deps "$file"
            ;;
        ruby)
            _scout_extract_ruby_deps "$file"
            ;;
        php)
            _scout_extract_php_deps "$file"
            ;;
        bash|shell)
            _scout_extract_shell_deps "$file"
            ;;
        *)
            echo '{"imports": [], "exports": []}'
            ;;
    esac
}

# Extract JavaScript/TypeScript dependencies
_scout_extract_js_deps() {
    local file="$1"
    
    python3 - "$file" <<'PYTHON'
import sys
import re
import json

filepath = sys.argv[1]

imports = []
exports = []

with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
    content = f.read()

# Import patterns
import_patterns = [
    r'import\s+(?:\{[^}]*\}|\*\s+as\s+\w+|\w+)\s+from\s+[\'"]([^\'"]+)[\'"]',
    r'import\s+[\'"]([^\'"]+)[\'"]',
    r'require\s*\(\s*[\'"]([^\'"]+)[\'"]\s*\)',
    r'import\(\s*[\'"]([^\'"]+)[\'"]\s*\)',
]

for pattern in import_patterns:
    for match in re.finditer(pattern, content):
        imports.append(match.group(1))

# Export patterns
export_patterns = [
    r'export\s+(?:default\s+)?(?:function|class|const|let|var|interface|type)\s+(\w+)',
    r'export\s+\{([^}]+)\}',
    r'export\s+\*\s+from\s+[\'"]([^\'"]+)[\'"]',
]

for pattern in export_patterns:
    for match in re.finditer(pattern, content):
        if match.lastindex >= 1:
            exports.append(match.group(1))

# Deduplicate
imports = list(set(imports))
exports = list(set(exports))

print(json.dumps({
    'file': filepath,
    'language': 'javascript' if filepath.endswith('.js') else 'typescript',
    'imports': imports,
    'exports': exports,
    'external_deps': [i for i in imports if not i.startswith('.') and not i.startswith('/')],
    'internal_deps': [i for i in imports if i.startswith('.') or i.startswith('/')]
}, indent=2))
PYTHON
}

# Extract Python dependencies
_scout_extract_python_deps() {
    local file="$1"
    
    python3 - "$file" <<'PYTHON'
import sys
import re
import json

filepath = sys.argv[1]

imports = []
exports = []

with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
    content = f.read()

# Import patterns
import_patterns = [
    r'^import\s+(\w+(?:\.\w+)*)',
    r'^from\s+(\w+(?:\.\w+)*)\s+import',
]

for pattern in import_patterns:
    for match in re.finditer(pattern, content, re.MULTILINE):
        imports.append(match.group(1))

# Export patterns (what this module provides)
export_patterns = [
    r'^def\s+(\w+)',
    r'^class\s+(\w+)',
    r'^__all__\s*=\s*\[([^\]]+)\]',
]

for pattern in export_patterns:
    for match in re.finditer(pattern, content, re.MULTILINE):
        if pattern.startswith(r'^__all__'):
            # Parse __all__ list
            items = re.findall(r'[\'"](\w+)[\'"]', match.group(1))
            exports.extend(items)
        else:
            exports.append(match.group(1))

# Deduplicate
imports = list(set(imports))
exports = list(set(exports))

print(json.dumps({
    'file': filepath,
    'language': 'python',
    'imports': imports,
    'exports': exports,
    'external_deps': [i for i in imports if '.' not in i or not i.startswith('.')],
    'internal_deps': [i for i in imports if i.startswith('.')]
}, indent=2))
PYTHON
}

# Extract Go dependencies
_scout_extract_go_deps() {
    local file="$1"
    
    python3 - "$file" <<'PYTHON'
import sys
import re
import json

filepath = sys.argv[1]

imports = []
exports = []

with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
    content = f.read()

# Import block
import_block = re.search(r'import\s*\((.*?)\)', content, re.DOTALL)
if import_block:
    for line in import_block.group(1).split('\n'):
        line = line.strip()
        if line and not line.startswith('//'):
            match = re.search(r'[\'"]([^\'"]+)[\'"]', line)
            if match:
                imports.append(match.group(1))

# Single import
single_imports = re.findall(r'import\s+[\'"]([^\'"]+)[\'"]', content)
imports.extend(single_imports)

# Exports (capitalized identifiers)
export_patterns = [
    r'func\s+([A-Z]\w*)',
    r'type\s+([A-Z]\w*)',
    r'var\s+([A-Z]\w*)',
    r'const\s+([A-Z]\w*)',
]

for pattern in export_patterns:
    for match in re.finditer(pattern, content):
        exports.append(match.group(1))

imports = list(set(imports))
exports = list(set(exports))

print(json.dumps({
    'file': filepath,
    'language': 'go',
    'imports': imports,
    'exports': exports,
    'external_deps': [i for i in imports if not i.startswith('.')],
    'internal_deps': [i for i in imports if i.startswith('.')]
}, indent=2))
PYTHON
}

# Extract Rust dependencies
_scout_extract_rust_deps() {
    local file="$1"
    
    python3 - "$file" <<'PYTHON'
import sys
import re
import json

filepath = sys.argv[1]

imports = []
exports = []

with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
    content = f.read()

# Use statements
use_patterns = [
    r'use\s+([^;]+);',
]

for pattern in use_patterns:
    for match in re.finditer(pattern, content):
        items = match.group(1).split(',')
        for item in items:
            item = item.strip().split('::')[0]
            if item and item not in ['crate', 'self', 'super']:
                imports.append(item)

# Exports (pub items)
export_patterns = [
    r'pub\s+fn\s+(\w+)',
    r'pub\s+struct\s+(\w+)',
    r'pub\s+enum\s+(\w+)',
    r'pub\s+const\s+(\w+)',
    r'pub\s+trait\s+(\w+)',
]

for pattern in export_patterns:
    for match in re.finditer(pattern, content):
        exports.append(match.group(1))

imports = list(set(imports))
exports = list(set(exports))

print(json.dumps({
    'file': filepath,
    'language': 'rust',
    'imports': imports,
    'exports': exports,
    'external_deps': imports,  # In Rust, external crates are in Cargo.toml
    'internal_deps': []
}, indent=2))
PYTHON
}

# Extract Java dependencies
_scout_extract_java_deps() {
    local file="$1"
    
    python3 - "$file" <<'PYTHON'
import sys
import re
import json

filepath = sys.argv[1]

imports = []
exports = []

with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
    content = f.read()

# Import statements
import_patterns = [
    r'import\s+(static\s+)?([\w.]+);',
]

for pattern in import_patterns:
    for match in re.finditer(pattern, content):
        imports.append(match.group(2))

# Exports (public classes/interfaces)
export_patterns = [
    r'public\s+class\s+(\w+)',
    r'public\s+interface\s+(\w+)',
    r'public\s+enum\s+(\w+)',
]

for pattern in export_patterns:
    for match in re.finditer(pattern, content):
        exports.append(match.group(1))

imports = list(set(imports))
exports = list(set(exports))

print(json.dumps({
    'file': filepath,
    'language': 'java',
    'imports': imports,
    'exports': exports,
    'external_deps': [i for i in imports if not i.startswith('java.') and not i.startswith('javax.')],
    'internal_deps': [i for i in imports if i.startswith('java.') or i.startswith('javax.')]
}, indent=2))
PYTHON
}

# Extract C/C++ dependencies
_scout_extract_c_deps() {
    local file="$1"
    
    python3 - "$file" <<'PYTHON'
import sys
import re
import json

filepath = sys.argv[1]

imports = []
exports = []

with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
    content = f.read()

# Include statements
include_patterns = [
    r'#include\s*<([^>]+)>',
    r'#include\s*"([^"]+)"',
]

for pattern in include_patterns:
    for match in re.finditer(pattern, content):
        imports.append(match.group(1))

# Exports (functions, structs, etc.)
export_patterns = [
    r'(?:extern\s+)?(?:static\s+)?(?:inline\s+)?\w+\s+(\w+)\s*\([^)]*\)\s*\{',
    r'typedef\s+struct\s+(\w+)',
    r'struct\s+(\w+)',
]

for pattern in export_patterns:
    for match in re.finditer(pattern, content):
        exports.append(match.group(1))

imports = list(set(imports))
exports = list(set(exports))

system_headers = ['stdio.h', 'stdlib.h', 'string.h', 'unistd.h', 'pthread.h', 
                  'stdint.h', 'stdbool.h', 'math.h', 'time.h', 'errno.h']

print(json.dumps({
    'file': filepath,
    'language': 'c' if filepath.endswith('.c') or filepath.endswith('.h') else 'cpp',
    'imports': imports,
    'exports': exports,
    'external_deps': [i for i in imports if i not in system_headers],
    'internal_deps': [i for i in imports if i in system_headers]
}, indent=2))
PYTHON
}

# Extract Ruby dependencies
_scout_extract_ruby_deps() {
    local file="$1"
    
    python3 - "$file" <<'PYTHON'
import sys
import re
import json

filepath = sys.argv[1]

imports = []
exports = []

with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
    content = f.read()

# Require statements
require_patterns = [
    r'require\s+[\'"]([^\'"]+)[\'"]',
    r'require_relative\s+[\'"]([^\'"]+)[\'"]',
    r'include\s+(\w+)',
    r'extend\s+(\w+)',
]

for pattern in require_patterns:
    for match in re.finditer(pattern, content):
        imports.append(match.group(1))

# Exports (methods, classes, modules)
export_patterns = [
    r'def\s+(\w+)',
    r'class\s+(\w+)',
    r'module\s+(\w+)',
]

for pattern in export_patterns:
    for match in re.finditer(pattern, content):
        exports.append(match.group(1))

imports = list(set(imports))
exports = list(set(exports))

print(json.dumps({
    'file': filepath,
    'language': 'ruby',
    'imports': imports,
    'exports': exports,
    'external_deps': [i for i in imports if not i.startswith('.') and not i.startswith('/')],
    'internal_deps': [i for i in imports if i.startswith('.') or i.startswith('/')]
}, indent=2))
PYTHON
}

# Extract PHP dependencies
_scout_extract_php_deps() {
    local file="$1"
    
    python3 - "$file" <<'PYTHON'
import sys
import re
import json

filepath = sys.argv[1]

imports = []
exports = []

with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
    content = f.read()

# Use/require statements
import_patterns = [
    r'use\s+([\w\\]+)',
    r'require(?:_once)?\s*[\'"]([^\'"]+)[\'"]',
    r'include(?:_once)?\s*[\'"]([^\'"]+)[\'"]',
]

for pattern in import_patterns:
    for match in re.finditer(pattern, content):
        imports.append(match.group(1))

# Exports (classes, functions)
export_patterns = [
    r'(?:public\s+)?(?:static\s+)?function\s+(\w+)',
    r'class\s+(\w+)',
    r'interface\s+(\w+)',
    r'trait\s+(\w+)',
]

for pattern in export_patterns:
    for match in re.finditer(pattern, content):
        exports.append(match.group(1))

imports = list(set(imports))
exports = list(set(exports))

print(json.dumps({
    'file': filepath,
    'language': 'php',
    'imports': imports,
    'exports': exports,
    'external_deps': [i for i in imports if '\\' in i],  # Namespaced = external
    'internal_deps': [i for i in imports if '\\' not in i]
}, indent=2))
PYTHON
}

# Extract Shell/Bash dependencies
_scout_extract_shell_deps() {
    local file="$1"
    
    python3 - "$file" <<'PYTHON'
import sys
import re
import json

filepath = sys.argv[1]

imports = []
exports = []

with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
    content = f.read()

# Source/dot commands
import_patterns = [
    r'^\.\s+([^\s;]+)',
    r'^source\s+([^\s;]+)',
]

for pattern in import_patterns:
    for match in re.finditer(pattern, content, re.MULTILINE):
        imports.append(match.group(1))

# Exports (functions)
export_patterns = [
    r'^(\w+)\s*\(\s*\)',
    r'^function\s+(\w+)',
]

for pattern in export_patterns:
    for match in re.finditer(pattern, content, re.MULTILINE):
        exports.append(match.group(1))

imports = list(set(imports))
exports = list(set(exports))

print(json.dumps({
    'file': filepath,
    'language': 'bash',
    'imports': imports,
    'exports': exports,
    'external_deps': [],
    'internal_deps': imports
}, indent=2))
PYTHON
}

# Analyze dependencies for entire directory
scout_analyze_deps() {
    local root_dir="${1:-.}"
    local exclude_patterns="${2:-$(scout_get_default_excludes)}"
    local output_format="${3:-json}"
    
    root_dir=$(scout_validate_dir "$root_dir")
    
    local find_args
    find_args=$(scout_parse_excludes "$exclude_patterns")
    
    # Collect all code files
    local files=()
    while IFS= read -r -d '' file; do
        files+=("$file")
    done < <(find "$root_dir" $find_args -type f -print0 2>/dev/null | grep -zZ '\.\(js\|ts\|py\|sh\|go\|rs\|java\|c\|cpp\|rb\|php\)$' || true)
    
    if [[ ${#files[@]} -eq 0 ]]; then
        echo '{"error": "No code files found", "files": []}'
        return 0
    fi
    
    case "$output_format" in
        json)
            echo '{"summary": {'
            echo '  "total_files": '${#files[@]}','
            echo '  "analyzed_at": "'"$(scout_timestamp)"'"'
            echo '},'
            echo '"files": ['
            
            local first=true
            for file in "${files[@]}"; do
                if [[ "$first" == true ]]; then
                    first=false
                else
                    echo ','
                fi
                scout_extract_deps "$file"
            done
            
            echo ''
            echo ']}'
            ;;
        markdown)
            echo "# Dependency Analysis Report"
            echo ""
            echo "**Directory:** $root_dir"
            echo "**Analyzed at:** $(scout_timestamp)"
            echo "**Total files:** ${#files[@]}"
            echo ""
            
            for file in "${files[@]}"; do
                local deps
                deps=$(scout_extract_deps "$file")
                
                local fname lang
                fname=$(echo "$deps" | python3 -c "import sys,json; print(json.load(sys.stdin)['file'])")
                lang=$(echo "$deps" | python3 -c "import sys,json; print(json.load(sys.stdin)['language'])")
                
                echo "## $fname"
                echo ""
                echo "**Language:** $lang"
                echo ""
                
                echo "### Imports"
                echo ""
                echo "$deps" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for imp in data.get('imports', [])[:20]:
    print(f'- {imp}')
if len(data.get('imports', [])) > 20:
    print(f'- ... and {len(data[\"imports\"]) - 20} more')
if not data.get('imports', []):
    print('- (none)')
"
                echo ""
                
                echo "### Exports"
                echo ""
                echo "$deps" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for exp in data.get('exports', [])[:20]:
    print(f'- {exp}')
if len(data.get('exports', [])) > 20:
    print(f'- ... and {len(data[\"exports\"]) - 20} more')
if not data.get('exports', []):
    print('- (none)')
"
                echo ""
                echo "---"
                echo ""
            done
            ;;
    esac
}

# Build dependency graph
scout_build_dep_graph() {
    local root_dir="${1:-.}"
    local exclude_patterns="${2:-$(scout_get_default_excludes)}"
    
    root_dir=$(scout_validate_dir "$root_dir")
    
    echo "digraph Dependencies {"
    echo "  rankdir=LR;"
    echo "  node [shape=box];"
    echo ""
    
    # Simple graph generation - would need more sophisticated analysis for real use
    local find_args
    find_args=$(scout_parse_excludes "$exclude_patterns")
    
    find "$root_dir" $find_args -name "*.py" -o -name "*.js" -o -name "*.ts" 2>/dev/null | \
    while read -r file; do
        local basename
        basename=$(basename "$file" | sed 's/\.[^.]*$//')
        echo "  \"$basename\";"
    done
    
    echo "}"
}
