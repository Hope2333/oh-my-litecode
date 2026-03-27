#!/usr/bin/env bash
#
# test-connection.sh - 连接测试脚本
#
# 该脚本用于测试 grep-app-enhanced 的各项连接功能：
# - Python 模块导入
# - MCP 服务器启动
# - GitHub API 连接
# - 本地搜索功能
# - 数据库初始化
#
# 用法:
#   ./test-connection.sh              # 运行所有测试
#   ./test-connection.sh --quick      # 快速测试（跳过网络）
#   ./test-connection.sh --module     # 仅测试模块导入
#   ./test-connection.sh --help       # 显示帮助
#
# 退出码:
#   0 - 所有测试通过
#   1 - 部分测试失败
#   2 - 严重错误
#
# Author: Oh My LiteCode Team
#

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 计数器
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++))
}

log_warning() {
    echo -e "${YELLOW}[SKIP]${NC} $1"
    ((TESTS_SKIPPED++))
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((TESTS_FAILED++))
}

log_header() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}========================================${NC}"
}

# 显示帮助
show_help() {
    cat << EOF
连接测试脚本

用法: $(basename "$0") [选项]

选项:
    --quick         快速测试（跳过网络和外部服务测试）
    --module        仅测试 Python 模块导入
    --mcp           仅测试 MCP 服务器
    --github        仅测试 GitHub 连接
    --verbose       显示详细输出
    --help          显示此帮助信息

测试项目:
    1. Python 模块导入测试
    2. ZSTD 压缩库测试
    3. 数据库初始化测试
    4. 本地搜索功能测试
    5. GitHub API 连接测试 (需要 GITHUB_TOKEN)
    6. MCP 服务器启动测试

退出码:
    0 - 所有测试通过
    1 - 部分测试失败
    2 - 严重错误（无法继续测试）
EOF
}

# 测试 Python 模块导入
test_module_import() {
    log_header "Python 模块导入测试"

    log_info "测试基础模块导入..."

    if python3 -c "from grep_app_enhanced import __version__; print(f'版本：{__version__}')" 2>/dev/null; then
        log_success "grep_app_enhanced 主模块"
    else
        log_error "grep_app_enhanced 主模块导入失败"
        return 1
    fi

    if python3 -c "from grep_app_enhanced.database import CompressedDatabase, CacheManager" 2>/dev/null; then
        log_success "database 模块"
    else
        log_error "database 模块导入失败"
        return 1
    fi

    if python3 -c "from grep_app_enhanced.remote import GitHubCLI, GitCrawler, GitClient" 2>/dev/null; then
        log_success "remote 模块"
    else
        log_error "remote 模块导入失败"
        return 1
    fi

    if python3 -c "from grep_app_enhanced.search import LocalSearch, RemoteSearch" 2>/dev/null; then
        log_success "search 模块"
    else
        log_error "search 模块导入失败"
        return 1
    fi

    if python3 -c "from grep_app_enhanced.mcp_server import main" 2>/dev/null; then
        log_success "mcp_server 模块"
    else
        log_error "mcp_server 模块导入失败"
        return 1
    fi

    return 0
}

# 测试 ZSTD 压缩库
test_zstd() {
    log_header "ZSTD 压缩库测试"

    log_info "测试 Python zstandard 包..."

    if python3 -c "
import zstandard as zstd
import sys

# 测试压缩
compressor = zstd.ZstdCompressor(level=3)
decompressor = zstd.ZstdDecompressor()

data = b'Hello, World! This is a test.'
compressed = compressor.compress(data)
decompressed = decompressor.decompress(compressed)

assert data == decompressed, '压缩/解压缩失败'
print(f'原始大小：{len(data)} 字节')
print(f'压缩大小：{len(compressed)} 字节')
print(f'压缩率：{len(compressed)/len(data)*100:.1f}%')
" 2>/dev/null; then
        log_success "ZSTD 压缩功能"
    else
        log_error "ZSTD 压缩功能测试失败"
        log_info "请运行 ./scripts/setup-zstd.sh 安装 ZSTD"
        return 1
    fi

    return 0
}

# 测试数据库初始化
test_database() {
    log_header "数据库初始化测试"

    local test_db="/tmp/grep_app_test_$$.db"

    log_info "测试压缩数据库初始化..."

    if python3 -c "
import asyncio
import sys
sys.path.insert(0, 'src')

from grep_app_enhanced.database import CompressedDatabase

async def test():
    db = CompressedDatabase('$test_db')
    await db.initialize()
    
    # 测试存储和检索
    from grep_app_enhanced import SearchResult
    results = [
        SearchResult(file_path='test.py', line_number=1, content='test')
    ]
    await db.store_search_results('test_hash', 'test', '.', results, ttl=60)
    
    retrieved = await db.retrieve_search_results('test_hash')
    assert retrieved is not None, '检索失败'
    assert len(retrieved) == 1, '结果数量错误'
    
    await db.close()
    print('数据库测试通过')

asyncio.run(test())
" 2>/dev/null; then
        log_success "压缩数据库功能"
        rm -f "$test_db"
    else
        log_error "压缩数据库功能测试失败"
        rm -f "$test_db"
        return 1
    fi

    return 0
}

# 测试缓存管理器
test_cache() {
    log_header "缓存管理器测试"

    log_info "测试缓存管理器..."

    if python3 -c "
import asyncio
import sys
sys.path.insert(0, 'src')

from grep_app_enhanced.database import CacheManager

async def test():
    cache = CacheManager(ttl=60, max_size=100)
    await cache.initialize()
    
    # 测试设置和获取
    await cache.set('key1', {'data': 'value1'})
    result = await cache.get('key1')
    assert result == {'data': 'value1'}, '缓存获取失败'
    
    # 测试删除
    await cache.delete('key1')
    result = await cache.get('key1')
    assert result is None, '删除失败'
    
    # 测试统计
    stats = cache.get_stats()
    print(f'命中率：{stats.hit_rate*100:.1f}%')
    
    await cache.close()
    print('缓存测试通过')

asyncio.run(test())
" 2>/dev/null; then
        log_success "缓存管理器功能"
    else
        log_error "缓存管理器功能测试失败"
        return 1
    fi

    return 0
}

# 测试本地搜索
test_local_search() {
    log_header "本地搜索功能测试"

    local test_dir="/tmp/grep_app_test_$$"
    mkdir -p "$test_dir"

    # 创建测试文件
    echo "def hello():
    print('Hello, World!')

def test_function():
    # TODO: implement this
    pass" > "$test_dir/test.py"

    log_info "测试本地搜索..."

    if python3 -c "
import asyncio
import sys
sys.path.insert(0, 'src')

from grep_app_enhanced.search import LocalSearch

async def test():
    search = LocalSearch()
    
    # 搜索函数定义
    results = await search.search(
        pattern=r'def \w+',
        path='$test_dir',
        include=['*.py']
    )
    
    print(f'找到 {len(results)} 个匹配')
    for r in results:
        print(f'  {r.file_path}:{r.line_number}: {r.content.strip()}')
    
    assert len(results) >= 2, '搜索结果数量错误'
    
    await search.close()
    print('本地搜索测试通过')

asyncio.run(test())
" 2>/dev/null; then
        log_success "本地搜索功能"
        rm -rf "$test_dir"
    else
        log_error "本地搜索功能测试失败"
        rm -rf "$test_dir"
        return 1
    fi

    return 0
}

# 测试 GitHub 连接
test_github() {
    log_header "GitHub API 连接测试"

    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
        log_warning "未设置 GITHUB_TOKEN，跳过 GitHub API 测试"
        log_info "设置环境变量后重试：export GITHUB_TOKEN=ghp_xxx"
        return 0
    fi

    log_info "测试 GitHub API 连接..."

    if python3 -c "
import asyncio
import sys
import os
sys.path.insert(0, 'src')

from grep_app_enhanced.remote import GitHubCLI

async def test():
    token = os.environ.get('GITHUB_TOKEN')
    gh = GitHubCLI(token=token)
    await gh.initialize()
    
    # 测试获取用户信息
    try:
        user = await gh.get_user_info()
        print(f'已认证用户：{user.get(\"login\", \"unknown\")}')
    except Exception as e:
        print(f'获取用户信息失败：{e}')
        return False
    
    # 测试搜索仓库
    repos = await gh.search_repos('python', language='Python', per_page=3)
    print(f'搜索到 {len(repos)} 个仓库')
    
    await gh.close()
    print('GitHub API 测试通过')
    return True

result = asyncio.run(test())
sys.exit(0 if result else 1)
" 2>/dev/null; then
        log_success "GitHub API 连接"
    else
        log_error "GitHub API 连接测试失败"
        log_info "检查 GITHUB_TOKEN 是否有效"
        return 1
    fi

    return 0
}

# 测试 MCP 服务器
test_mcp_server() {
    log_header "MCP 服务器测试"

    log_info "测试 MCP 服务器初始化..."

    if python3 -c "
import asyncio
import sys
sys.path.insert(0, 'src')

from grep_app_enhanced.mcp_server import GrepAppMCPServer

async def test():
    server = GrepAppMCPServer()
    await server.initialize()
    
    # 测试本地搜索工具
    results = await server.search_local(
        pattern='test',
        path='.',
        max_results=5
    )
    print(f'本地搜索返回 {len(results)} 个结果')
    
    # 测试缓存统计
    stats = await server.get_cache_stats()
    print(f'缓存状态：{\"enabled\" if stats.get(\"enabled\") else \"disabled\"}')
    
    await server.shutdown()
    print('MCP 服务器测试通过')

asyncio.run(test())
" 2>/dev/null; then
        log_success "MCP 服务器功能"
    else
        log_error "MCP 服务器功能测试失败"
        return 1
    fi

    return 0
}

# 显示测试摘要
show_summary() {
    echo ""
    echo "========================================"
    echo "  测试摘要"
    echo "========================================"
    echo -e "  ${GREEN}通过：$TESTS_PASSED${NC}"
    echo -e "  ${RED}失败：$TESTS_FAILED${NC}"
    echo -e "  ${YELLOW}跳过：$TESTS_SKIPPED${NC}"
    echo "========================================"

    local total=$((TESTS_PASSED + TESTS_FAILED))
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}所有测试通过!${NC}"
        return 0
    else
        echo -e "${RED}部分测试失败${NC}"
        return 1
    fi
}

# 主函数
main() {
    local quick_test=false
    local module_only=false
    local mcp_only=false
    local github_only=false
    local verbose=false

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --quick)
                quick_test=true
                shift
                ;;
            --module)
                module_only=true
                shift
                ;;
            --mcp)
                mcp_only=true
                shift
                ;;
            --github)
                github_only=true
                shift
                ;;
            --verbose)
                verbose=true
                set -x
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                echo "未知选项：$1"
                show_help
                exit 2
                ;;
        esac
    done

    echo ""
    echo "========================================"
    echo "  Grep App Enhanced 连接测试"
    echo "========================================"
    echo ""

    # 检查 Python 环境
    if ! command -v python3 &> /dev/null; then
        log_error "未找到 Python 3"
        exit 2
    fi

    # 检查模块是否已安装
    if ! python3 -c "import grep_app_enhanced" 2>/dev/null; then
        log_error "grep-app-enhanced 未安装"
        log_info "请先运行：pip install -e ."
        exit 2
    fi

    # 运行测试
    if [[ "$module_only" == "true" ]]; then
        test_module_import
    elif [[ "$mcp_only" == "true" ]]; then
        test_mcp_server
    elif [[ "$github_only" == "true" ]]; then
        test_github
    else
        test_module_import || exit 2
        test_zstd || true
        test_database || true
        test_cache || true
        test_local_search || true

        if [[ "$quick_test" != "true" ]]; then
            test_github || true
            test_mcp_server || true
        fi
    fi

    # 显示摘要
    show_summary
    exit $?
}

# 运行主函数
main "$@"
