#!/usr/bin/env bash
# Scout Plugin - Code Complexity Analysis

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# Analyze code complexity for a file
scout_analyze_file_complexity() {
    local file="$1"
    
    if [[ ! -f "$file" ]]; then
        scout_error "File not found: $file"
        return 1
    fi
    
    local lang
    lang=$(scout_detect_language "$file")
    
    local total_lines code_lines blank_lines comment_lines
    total_lines=$(wc -l < "$file" | tr -d ' ')
    blank_lines=$(grep -c '^\s*$' "$file" 2>/dev/null || echo "0")
    comment_lines=$(_scout_count_comments "$file" "$lang")
    code_lines=$((total_lines - blank_lines - comment_lines))
    
    # Calculate cyclomatic complexity approximation
    local complexity
    complexity=$(_scout_calculate_complexity "$file" "$lang")
    complexity=${complexity:-1}
    complexity=$(echo "$complexity" | tr -d '[:space:]')
    [[ -z "$complexity" || "$complexity" == "0" ]] && complexity=1

    # Count functions/methods
    local func_count
    func_count=$(_scout_count_functions "$file" "$lang")
    func_count=${func_count:-0}
    func_count=$(echo "$func_count" | tr -d '[:space:]')
    [[ -z "$func_count" ]] && func_count=0

    # Get average function length
    local avg_func_length=0
    if [[ $func_count -gt 0 ]]; then
        avg_func_length=$((code_lines / func_count))
    fi

    # Calculate comment ratio
    local comment_ratio="0"
    if [[ $total_lines -gt 0 ]]; then
        comment_ratio=$(awk "BEGIN {printf \"%.2f\", $comment_lines / $total_lines}")
    fi

    # Get complexity level
    local complexity_level
    complexity_level=$(_scout_complexity_level "$complexity")

    # Output JSON
    cat <<EOF
{
  "file": "$(scout_json_escape "$file")",
  "language": "$lang",
  "metrics": {
    "total_lines": $total_lines,
    "code_lines": $code_lines,
    "blank_lines": $blank_lines,
    "comment_lines": $comment_lines,
    "comment_ratio": $comment_ratio,
    "cyclomatic_complexity": $complexity,
    "function_count": $func_count,
    "avg_function_length": $avg_func_length
  },
  "complexity_level": "$complexity_level"
}
EOF
}

# Count comment lines based on language
_scout_count_comments() {
    local file="$1"
    local lang="$2"
    local count=0

    case "$lang" in
        javascript|typescript|java|cpp|c|go|rust|swift|kotlin|scala)
            count=$(grep -c '^\s*//' "$file" 2>/dev/null || echo "0")
            count=$(echo "$count" | tr -d '[:space:]')
            [[ -z "$count" ]] && count=0
            local block_comments
            block_comments=$(grep -c '^\s*/\*\|^\s*\*\|^\s*\*/' "$file" 2>/dev/null || echo "0")
            block_comments=$(echo "$block_comments" | tr -d '[:space:]')
            [[ -z "$block_comments" ]] && block_comments=0
            count=$((count + block_comments))
            ;;
        python|ruby|bash|perl|yaml|shell)
            count=$(grep -c '^\s*#' "$file" 2>/dev/null || echo "0")
            count=$(echo "$count" | tr -d '[:space:]')
            [[ -z "$count" ]] && count=0
            ;;
        lua)
            count=$(grep -c '^\s*--' "$file" 2>/dev/null || echo "0")
            count=$(echo "$count" | tr -d '[:space:]')
            [[ -z "$count" ]] && count=0
            ;;
        html)
            count=$(grep -c '<!--' "$file" 2>/dev/null || echo "0")
            count=$(echo "$count" | tr -d '[:space:]')
            [[ -z "$count" ]] && count=0
            ;;
        *)
            count=0
            ;;
    esac

    echo "$count"
}

# Calculate cyclomatic complexity approximation
_scout_calculate_complexity() {
    local file="$1"
    local lang="$2"
    local complexity=1  # Base complexity

    case "$lang" in
        javascript|typescript|java|cpp|c|go|rust|swift|kotlin|scala)
            # Count: if, else if, for, while, case, catch, &&, ||, ?
            local branches
            branches=$(grep -cE '\b(if|else if|for|while|case|catch)\s*[\(]' "$file" 2>/dev/null || echo "0")
            branches=$(echo "$branches" | tr -d '[:space:]')
            [[ -z "$branches" ]] && branches=0
            local operators
            operators=$(grep -oE '(\&\&|\|\||\?)' "$file" 2>/dev/null | wc -l | tr -d ' ')
            operators=$(echo "$operators" | tr -d '[:space:]')
            [[ -z "$operators" ]] && operators=0
            complexity=$((1 + branches + operators))
            ;;
        python)
            # Count: if, elif, for, while, except, and, or
            local branches
            branches=$(grep -cE '^\s*(if|elif|for|while|except)\b' "$file" 2>/dev/null || echo "0")
            branches=$(echo "$branches" | tr -d '[:space:]')
            [[ -z "$branches" ]] && branches=0
            local operators
            operators=$(grep -cE '\b(and|or)\b' "$file" 2>/dev/null || echo "0")
            operators=$(echo "$operators" | tr -d '[:space:]')
            [[ -z "$operators" ]] && operators=0
            complexity=$((1 + branches + operators))
            ;;
        bash|shell)
            # Count: if, elif, for, while, case, &&, ||
            local branches
            branches=$(grep -cE '^\s*(if|elif|for|while|case)\b' "$file" 2>/dev/null || echo "0")
            branches=$(echo "$branches" | tr -d '[:space:]')
            [[ -z "$branches" ]] && branches=0
            local operators
            operators=$(grep -cE '(\&\&|\|\|)' "$file" 2>/dev/null || echo "0")
            operators=$(echo "$operators" | tr -d '[:space:]')
            [[ -z "$operators" ]] && operators=0
            complexity=$((1 + branches + operators))
            ;;
        ruby)
            local branches
            branches=$(grep -cE '\b(if|elsif|unless|for|while|case|when|rescue)\b' "$file" 2>/dev/null || echo "0")
            branches=$(echo "$branches" | tr -d '[:space:]')
            [[ -z "$branches" ]] && branches=0
            complexity=$((1 + branches))
            ;;
        *)
            complexity=1
            ;;
    esac

    # Ensure complexity is a clean integer
    complexity=$(echo "$complexity" | tr -d '[:space:]')
    [[ -z "$complexity" || ! "$complexity" =~ ^[0-9]+$ ]] && complexity=1
    
    echo "$complexity"
}

# Count functions/methods
_scout_count_functions() {
    local file="$1"
    local lang="$2"
    local count=0

    case "$lang" in
        javascript|typescript)
            count=$(grep -cE '(function\s+\w+|(\w+)\s*=>|\w+\s*\([^)]*\)\s*\{|async\s+\w+\s*\()' "$file" 2>/dev/null || echo "0")
            ;;
        python)
            count=$(grep -cE '^\s*def\s+\w+' "$file" 2>/dev/null || echo "0")
            ;;
        java|cpp|c|go|rust|swift|kotlin|scala)
            count=$(grep -cE '\b(function|func|fn|def)\s+\w+' "$file" 2>/dev/null || echo "0")
            ;;
        bash|shell)
            count=$(grep -cE '^\s*(\w+\s*\(\s*\)|function\s+\w+)' "$file" 2>/dev/null || echo "0")
            ;;
        ruby)
            count=$(grep -cE '^\s*def\s+\w+' "$file" 2>/dev/null || echo "0")
            ;;
        php)
            count=$(grep -cE '\bfunction\s+\w+' "$file" 2>/dev/null || echo "0")
            ;;
        *)
            count=0
            ;;
    esac

    # Ensure count is a clean integer
    count=$(echo "$count" | tr -d '[:space:]')
    if [[ -z "$count" ]] || ! [[ "$count" =~ ^[0-9]+$ ]]; then
        count=0
    fi
    # Remove leading zeros but keep at least one digit
    count=$((count + 0))
    
    echo "$count"
}

# Get complexity level description
_scout_complexity_level() {
    local complexity=$1
    
    if [[ $complexity -le 5 ]]; then
        echo "low"
    elif [[ $complexity -le 10 ]]; then
        echo "medium"
    elif [[ $complexity -le 20 ]]; then
        echo "high"
    else
        echo "very_high"
    fi
}

# Analyze entire directory
scout_analyze_directory() {
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
                scout_analyze_file_complexity "$file"
            done
            
            echo ''
            echo ']}'
            ;;
        markdown)
            echo "# Code Complexity Analysis"
            echo ""
            echo "**Directory:** $root_dir"
            echo "**Analyzed at:** $(scout_timestamp)"
            echo "**Total files:** ${#files[@]}"
            echo ""
            echo "## File Details"
            echo ""
            echo "| File | Language | Lines | Complexity | Functions | Level |"
            echo "|------|----------|-------|------------|-----------|-------|"
            
            for file in "${files[@]}"; do
                local analysis
                analysis=$(scout_analyze_file_complexity "$file")
                
                local fname lang lines complexity funcs level
                fname=$(echo "$analysis" | python3 -c "import sys,json; print(json.load(sys.stdin)['file'])")
                lang=$(echo "$analysis" | python3 -c "import sys,json; print(json.load(sys.stdin)['language'])")
                lines=$(echo "$analysis" | python3 -c "import sys,json; print(json.load(sys.stdin)['metrics']['code_lines'])")
                complexity=$(echo "$analysis" | python3 -c "import sys,json; print(json.load(sys.stdin)['metrics']['cyclomatic_complexity'])")
                funcs=$(echo "$analysis" | python3 -c "import sys,json; print(json.load(sys.stdin)['metrics']['function_count'])")
                level=$(echo "$analysis" | python3 -c "import sys,json; print(json.load(sys.stdin)['complexity_level'])")
                
                local rel_path="${file#$root_dir/}"
                echo "| $rel_path | $lang | $lines | $complexity | $funcs | $level |"
            done
            ;;
    esac
}

# Get complexity summary statistics
scout_complexity_summary() {
    local root_dir="${1:-.}"
    local exclude_patterns="${2:-$(scout_get_default_excludes)}"
    
    root_dir=$(scout_validate_dir "$root_dir")
    
    python3 - "$root_dir" "$exclude_patterns" <<'PYTHON'
import os
import sys
import json
import subprocess

def analyze_file(filepath):
    """Analyze a single file's complexity."""
    try:
        result = subprocess.run(
            ['bash', '-c', f'source {sys.argv[0]}/../lib/utils.sh; scout_analyze_file_complexity "{filepath}"'],
            capture_output=True, text=True, timeout=30
        )
        if result.returncode == 0:
            return json.loads(result.stdout)
    except:
        pass
    return None

def get_code_files(root_dir, exclude_patterns):
    """Get all code files."""
    exclude_list = [p.strip() for p in exclude_patterns.split(',') if p.strip()]
    code_extensions = {'.js', '.ts', '.py', '.sh', '.go', '.rs', '.java', '.c', '.cpp', '.rb', '.php'}
    
    files = []
    for dirpath, dirnames, filenames in os.walk(root_dir):
        # Filter excluded dirs
        dirnames[:] = [d for d in dirnames if d not in exclude_list]
        
        for filename in filenames:
            ext = os.path.splitext(filename)[1].lower()
            if ext in code_extensions:
                files.append(os.path.join(dirpath, filename))
    
    return files

root_dir = sys.argv[1]
exclude_patterns = sys.argv[2] if len(sys.argv) > 2 else ""

files = get_code_files(root_dir, exclude_patterns)

total_complexity = 0
total_functions = 0
total_lines = 0
high_complexity_files = []

for filepath in files[:100]:  # Limit to 100 files for performance
    analysis = analyze_file(filepath)
    if analysis and 'metrics' in analysis:
        metrics = analysis['metrics']
        total_complexity += metrics.get('cyclomatic_complexity', 0)
        total_functions += metrics.get('function_count', 0)
        total_lines += metrics.get('code_lines', 0)
        
        if analysis.get('complexity_level') in ['high', 'very_high']:
            high_complexity_files.append({
                'file': analysis['file'],
                'complexity': metrics.get('cyclomatic_complexity', 0)
            })

file_count = len(files)
avg_complexity = total_complexity / file_count if file_count > 0 else 0

print(json.dumps({
    'total_files': file_count,
    'total_lines': total_lines,
    'total_functions': total_functions,
    'average_complexity': round(avg_complexity, 2),
    'high_complexity_files': sorted(high_complexity_files, key=lambda x: x['complexity'], reverse=True)[:10]
}, indent=2))
PYTHON
}
