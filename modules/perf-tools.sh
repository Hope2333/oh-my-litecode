#!/usr/bin/env bash
# OML Performance Optimization Module
# Tools for monitoring and optimizing OML performance
#
# Usage:
#   oml perf benchmark    # Run benchmarks
#   oml perf profile      # Profile performance
#   oml perf optimize     # Apply optimizations
#   oml perf status       # Show performance status

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
OML_ROOT="${OML_ROOT:-${HOME}/develop/oh-my-litecode}"
CACHE_DIR="${HOME}/.oml/cache"
PERF_LOG="${HOME}/.oml/perf.log"

# Print step
print_step() {
    echo -e "${BLUE}==>${NC} $1"
}

# Print success
print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

# Print error
print_error() {
    echo -e "${RED}✗${NC} $1" >&2
}

# Print warning
print_warning() {
    echo -e "${YELLOW}!${NC} $1"
}

# Benchmark startup time
benchmark_startup() {
    print_step "Benchmarking startup time..."
    
    local start_time end_time duration
    start_time=$(date +%s%N)
    
    # Source OML
    source "${OML_ROOT}/core/platform.sh" 2>/dev/null
    
    end_time=$(date +%s%N)
    duration=$(( (end_time - start_time) / 1000000 ))
    
    echo "Startup Time: ${duration}ms"
    
    if [[ $duration -lt 100 ]]; then
        echo -e "Status: ${GREEN}Excellent${NC}"
    elif [[ $duration -lt 500 ]]; then
        echo -e "Status: ${YELLOW}Good${NC}"
    else
        echo -e "Status: ${RED}Slow${NC}"
    fi
}

# Benchmark command execution
benchmark_command() {
    local cmd="$1"
    
    print_step "Benchmarking: $cmd"
    
    local start_time end_time duration
    start_time=$(date +%s%N)
    
    # Run command 10 times
    for i in {1..10}; do
        eval "$cmd" >/dev/null 2>&1
    done
    
    end_time=$(date +%s%N)
    duration=$(( (end_time - start_time) / 10000000 ))
    
    echo "Average Time: ${duration}ms (10 runs)"
}

# Check cache performance
check_cache() {
    print_step "Checking cache performance..."
    
    if [[ ! -d "$CACHE_DIR" ]]; then
        echo -e "Cache: ${YELLOW}Not initialized${NC}"
        return 0
    fi
    
    local cache_size cache_files
    cache_size=$(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1)
    cache_files=$(find "$CACHE_DIR" -type f 2>/dev/null | wc -l)
    
    echo "Cache Size: $cache_size"
    echo "Cache Files: $cache_files"
    
    # Check hit rate (placeholder)
    echo -e "Hit Rate: ${YELLOW}Monitoring...${NC}"
}

# Memory usage
check_memory() {
    print_step "Checking memory usage..."
    
    # Get OML process memory (placeholder)
    local mem_usage
    mem_usage=$(ps aux | grep -E "oml|bash" | head -5 | awk '{sum+=$6} END {print sum/1024}')
    
    echo "Memory Usage: ${mem_usage}MB"
    
    if (( $(echo "$mem_usage < 50" | bc -l 2>/dev/null || echo 1) )); then
        echo -e "Status: ${GREEN}Good${NC}"
    else
        echo -e "Status: ${YELLOW}High${NC}"
    fi
}

# Apply optimizations
cmd_optimize() {
    print_step "Applying optimizations..."
    
    # Enable bash optimizations
    print_step "Enabling bash optimizations..."
    
    # Create optimized bashrc snippet
    local optim_file="${HOME}/.oml/optimized-bash.sh"
    
    cat > "$optim_file" <<'EOF'
# OML Bash Optimizations

# Disable history for faster execution
set +o history

# Faster globbing
shopt -s dotglob nullglob

# Faster variable expansion
export LC_ALL=C

# Faster command lookup
hash -r
EOF
    
    print_success "Optimizations created: $optim_file"
    
    # Clear cache
    print_step "Clearing old cache..."
    if [[ -d "$CACHE_DIR" ]]; then
        rm -rf "$CACHE_DIR"/*
        print_success "Cache cleared"
    fi
    
    # Initialize cache
    mkdir -p "$CACHE_DIR"
    
    print_success "Optimizations applied"
}

# Run full benchmark
cmd_benchmark() {
    echo "╔═══════════════════════════════════════╗"
    echo "║     OML Performance Benchmark         ║"
    echo "╚═══════════════════════════════════════╝"
    echo ""
    
    benchmark_startup
    echo ""
    
    benchmark_command "oml --help"
    echo ""
    
    benchmark_command "oml plugins list"
    echo ""
    
    check_cache
    echo ""
    
    check_memory
    echo ""
    
    print_success "Benchmark complete"
}

# Profile performance
cmd_profile() {
    print_step "Profiling performance..."
    
    echo "Performance Profile:"
    echo ""
    
    # System info
    echo "System:"
    echo "  CPU: $(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 || echo 'Unknown')"
    echo "  Memory: $(free -h | grep Mem | awk '{print $2}' || echo 'Unknown')"
    echo "  Disk: $(df -h / | tail -1 | awk '{print $2}' || echo 'Unknown')"
    echo ""
    
    # OML stats
    echo "OML Stats:"
    echo "  Root: $OML_ROOT"
    echo "  Plugins: $(find "${OML_ROOT}/plugins" -name "*.sh" 2>/dev/null | wc -l)"
    echo "  Modules: $(find "${OML_ROOT}/modules" -name "*.sh" 2>/dev/null | wc -l)"
    echo ""
    
    # Performance metrics
    echo "Performance Metrics:"
    check_cache
    echo ""
    check_memory
}

# Show performance status
cmd_status() {
    echo "OML Performance Status:"
    echo ""
    
    # Startup time
    local start_time end_time duration
    start_time=$(date +%s%N)
    source "${OML_ROOT}/core/platform.sh" 2>/dev/null
    end_time=$(date +%s%N)
    duration=$(( (end_time - start_time) / 1000000 ))
    
    echo "Startup Time: ${duration}ms"
    
    # Cache status
    if [[ -d "$CACHE_DIR" ]]; then
        local cache_size
        cache_size=$(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1)
        echo "Cache: ${cache_size}"
    else
        echo "Cache: Not initialized"
    fi
    
    # Memory
    check_memory >/dev/null
    echo ""
    
    # Recommendations
    echo "Recommendations:"
    if [[ $duration -gt 500 ]]; then
        echo "  - Consider running 'oml perf optimize'"
    fi
    if [[ -d "$CACHE_DIR" ]]; then
        echo "  - Cache is active"
    else
        echo "  - Consider enabling cache"
    fi
}

# Show help
print_help() {
    cat <<EOF
OML Performance Tools

Usage: oml perf <command>

Commands:
  benchmark     Run full benchmark suite
  profile       Profile current performance
  optimize      Apply performance optimizations
  status        Show performance status
  help          Show this help

Examples:
  oml perf benchmark    # Run benchmarks
  oml perf profile      # Profile performance
  oml perf optimize     # Apply optimizations
  oml perf status       # Show status

Optimizations:
  - Bash startup optimization
  - Cache clearing
  - Memory management
  - Command lookup optimization

EOF
}

# Main function
main() {
    local command="${1:-help}"
    shift || true
    
    case "$command" in
        benchmark)
            cmd_benchmark
            ;;
        profile)
            cmd_profile
            ;;
        optimize)
            cmd_optimize
            ;;
        status)
            cmd_status
            ;;
        help|--help|-h)
            print_help
            ;;
        *)
            print_error "Unknown command: $command"
            print_help
            exit 1
            ;;
    esac
}

main "$@"
