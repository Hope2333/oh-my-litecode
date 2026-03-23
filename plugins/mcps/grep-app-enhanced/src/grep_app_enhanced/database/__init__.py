"""
Database 模块 - 提供压缩数据库和缓存管理功能.

本模块包含：
- CompressedDatabase: ZSTD 压缩的 SQLite 数据库
- CacheManager: 智能缓存管理器
- 工具函数和辅助类

Example:
    ```python
    from grep_app_enhanced.database import CompressedDatabase, CacheManager
    from grep_app_enhanced.database import compute_query_hash, PerformanceTracker

    async with CompressedDatabase("cache.db") as db:
        await db.store("key", "value")

    cache = CacheManager(ttl=3600)
    await cache.set("key", "value")
    ```
"""

from __future__ import annotations

from .cache_manager import (
    CacheManager,
    CacheEntry,
    CacheStats,
    CacheMonitor,
    CacheManagerFactory,
    EvictionPolicy,
    LRUPolicy,
    LFUPolicy,
    TTLPolicy,
    PriorityPolicy,
)
from .compressed_db import (
    CompressedDatabase,
    CompressionStats,
    DatabaseConfig,
    ConnectionPool,
    CompressedDatabaseError,
    CompressionError as DBCompressionError,
    DatabaseConnectionError,
    DatabaseOperationError,
    compute_query_hash,
    compressed_database_context,
)
from .utils import (
    # 哈希工具
    compute_hash,
    compute_file_hash,
    # 序列化
    JsonSerializer,
    BinarySerializer,
    # 性能分析
    PerformanceMetrics,
    PerformanceTracker,
    timed,
    # 重试
    RetryConfig,
    retry,
    # 内存管理
    MemoryManager,
    # 批量处理
    batch_process,
    # 限流器
    RateLimiter,
    # 缓存键
    CacheKeyGenerator,
    # 错误处理
    DatabaseError,
    CacheError,
    SerializationError,
    CompressionError,
    handle_errors,
    # 验证
    validate_compression_ratio,
    validate_cache_entry,
    # 日志
    LogContext,
)

__all__ = [
    # 主类
    "CompressedDatabase",
    "CacheManager",
    # 数据类
    "CompressionStats",
    "CacheEntry",
    "CacheStats",
    "CacheMonitor",
    "PerformanceMetrics",
    # 配置类
    "DatabaseConfig",
    "RetryConfig",
    # 连接池
    "ConnectionPool",
    # 工厂类
    "CacheManagerFactory",
    # 淘汰策略
    "EvictionPolicy",
    "LRUPolicy",
    "LFUPolicy",
    "TTLPolicy",
    "PriorityPolicy",
    # 工具类
    "JsonSerializer",
    "BinarySerializer",
    "PerformanceTracker",
    "MemoryManager",
    "RateLimiter",
    "CacheKeyGenerator",
    "LogContext",
    # 上下文管理器
    "compressed_database_context",
    "handle_errors",
    # 装饰器
    "timed",
    "retry",
    # 函数
    "compute_query_hash",
    "compute_hash",
    "compute_file_hash",
    "batch_process",
    "validate_compression_ratio",
    "validate_cache_entry",
    # 异常
    "CompressedDatabaseError",
    "DBCompressionError",
    "CompressionError",
    "DatabaseConnectionError",
    "DatabaseOperationError",
    "DatabaseError",
    "CacheError",
    "SerializationError",
]
