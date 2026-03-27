"""
Search 模块 - 本地和远程搜索功能（增强版：三层缓存 + 智能降级）.

本模块提供全面的代码搜索能力，支持：
- 本地文件系统搜索
- 远程仓库搜索（三层缓存）
- 正则表达式匹配
- 智能缓存（L1 SQLite+ZSTD, L2 Git, L3 Remote）
- 并行处理
- 智能降级策略

Example:
    ```python
    from grep_app_enhanced.search import LocalSearch, RemoteSearch, FallbackStrategy

    # 三层缓存搜索
    remote = RemoteSearch(db_path="/tmp/grep.db", git_cache_dir="/tmp/git-cache")
    await remote.initialize()
    results, stats = await remote.search_with_three_layer_cache("pattern", repo="owner/repo")

    # 智能降级
    strategy = FallbackStrategy()
    await strategy.initialize()
    result = await strategy.execute_with_fallback(search_func, fallback_chain=[...])
    ```

Search Modes:
    - literal: 字面匹配
    - regex: 正则表达式
    - glob: 通配符匹配

Cache Layers:
    - L1: SQLite+ZSTD 压缩缓存（毫秒级响应）
    - L2: 本地 Git 仓库缓存（秒级响应）
    - L3: 远程通路查询（依赖网络）

Author:
    Oh My LiteCode Team
"""

from __future__ import annotations

from .local_search import LocalSearch
from .remote_search import (
    RemoteSearch,
    RemoteSearchConfig,
    SearchStatistics,
    ThreeLayerCacheStats,
    CacheLayer,
)
from .intelligent_fallback import (
    FallbackStrategy,
    FallbackConfig,
    FallbackResult,
    FallbackLevel,
    PathwayMetrics,
    PathwayHealth,
    CircuitBreaker,
    DEFAULT_FALLBACK_CONFIG,
    FAST_FALLBACK_CONFIG,
    RELIABLE_FALLBACK_CONFIG,
)

__all__ = [
    "LocalSearch",
    "RemoteSearch",
    "RemoteSearchConfig",
    "SearchStatistics",
    "ThreeLayerCacheStats",
    "CacheLayer",
    "FallbackStrategy",
    "FallbackConfig",
    "FallbackResult",
    "FallbackLevel",
    "PathwayMetrics",
    "PathwayHealth",
    "CircuitBreaker",
    "DEFAULT_FALLBACK_CONFIG",
    "FAST_FALLBACK_CONFIG",
    "RELIABLE_FALLBACK_CONFIG",
]
