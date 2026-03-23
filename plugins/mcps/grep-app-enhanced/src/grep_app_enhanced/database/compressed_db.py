"""
Compressed Database - ZSTD 压缩的 SQLite 数据库模块.

本模块提供基于 SQLite 的压缩数据库实现，使用 ZSTD 算法进行数据压缩，
显著减少存储空间占用，同时保持快速的读写性能.

Features:
    - 透明的 ZSTD 压缩/解压缩
    - 异步 I/O 支持
    - 连接池管理
    - 自动模式迁移
    - 压缩统计信息
    - 并发读取支持
    - 自动清理过期数据

Example:
    ```python
    from grep_app_enhanced.database import CompressedDatabase

    async with CompressedDatabase("data.db", compression_level=3) as db:
        await db.execute("CREATE TABLE IF NOT EXISTS cache (key TEXT, value BLOB)")
        await db.store("my_key", b"some data")
        data = await db.retrieve("my_key")
    ```

Compression Levels:
    - 1-3: 快速压缩，适合频繁写入
    - 4-9: 平衡模式，推荐默认使用
    - 10-22: 高压缩率，适合归档数据

Performance Targets:
    - 压缩比：5:1 以上
    - 读性能影响：<15%
    - 写性能影响：<25%

Author:
    Oh My LiteCode Team
"""

from __future__ import annotations

import asyncio
import hashlib
import json
import logging
import sqlite3
import sys
import threading
import time
import zlib
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from contextlib import asynccontextmanager
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, AsyncIterator, Callable, Optional

import zstandard as zstd

from ..__init__ import SearchResult

# 配置日志
logger = logging.getLogger(__name__)

# 如果未配置处理器，添加默认处理器
if not logger.handlers:
    handler = logging.StreamHandler(sys.stdout)
    handler.setLevel(logging.DEBUG)
    formatter = logging.Formatter(
        "%(asctime)s - %(name)s - %(levelname)s - %(message)s"
    )
    handler.setFormatter(formatter)
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)


@dataclass
class CompressionStats:
    """压缩统计数据类.

    Attributes:
        original_size: 原始数据大小（字节）
        compressed_size: 压缩后大小（字节）
        compression_ratio: 压缩比率 (compressed/original)
        compress_time_ms: 压缩耗时（毫秒）
        decompress_time_ms: 解压缩耗时（毫秒）
        operation_count: 操作次数

    Example:
        ```python
        stats = CompressionStats(
            original_size=10000,
            compressed_size=3000,
            compression_ratio=0.3,
            compress_time_ms=1.5,
            decompress_time_ms=0.8
        )
        print(f"压缩率：{stats.compression_ratio:.2%}")
        print(f"压缩比：{1/stats.compression_ratio:.1f}:1")
        ```
    """

    original_size: int = 0
    compressed_size: int = 0
    compression_ratio: float = 0.0
    compress_time_ms: float = 0.0
    decompress_time_ms: float = 0.0
    operation_count: int = 0

    @property
    def space_saved(self) -> int:
        """计算节省的空间（字节）."""
        return max(0, self.original_size - self.compressed_size)

    @property
    def space_saved_percent(self) -> float:
        """计算节省空间的百分比."""
        if self.original_size == 0:
            return 0.0
        return (self.space_saved / self.original_size) * 100

    @property
    def compression_ratio_display(self) -> str:
        """获取可读的压缩比显示 (如 5:1)."""
        if self.compression_ratio <= 0:
            return "N/A"
        ratio = 1.0 / self.compression_ratio
        return f"{ratio:.1f}:1"

    @property
    def avg_compress_time_ms(self) -> float:
        """获取平均压缩时间."""
        if self.operation_count == 0:
            return 0.0
        return self.compress_time_ms / self.operation_count

    @property
    def avg_decompress_time_ms(self) -> float:
        """获取平均解压缩时间."""
        if self.operation_count == 0:
            return 0.0
        return self.decompress_time_ms / self.operation_count

    def to_dict(self) -> dict[str, Any]:
        """转换为字典格式."""
        return {
            "original_size": self.original_size,
            "compressed_size": self.compressed_size,
            "compression_ratio": self.compression_ratio,
            "compression_ratio_display": self.compression_ratio_display,
            "compress_time_ms": self.compress_time_ms,
            "decompress_time_ms": self.decompress_time_ms,
            "space_saved": self.space_saved,
            "space_saved_percent": self.space_saved_percent,
            "operation_count": self.operation_count,
            "avg_compress_time_ms": self.avg_compress_time_ms,
            "avg_decompress_time_ms": self.avg_decompress_time_ms,
        }

    def reset(self) -> None:
        """重置统计数据."""
        self.original_size = 0
        self.compressed_size = 0
        self.compression_ratio = 0.0
        self.compress_time_ms = 0.0
        self.decompress_time_ms = 0.0
        self.operation_count = 0


class CompressedDatabaseError(Exception):
    """压缩数据库异常基类."""
    pass


class CompressionError(CompressedDatabaseError):
    """压缩/解压缩错误."""
    pass


class DatabaseConnectionError(CompressedDatabaseError):
    """数据库连接错误."""
    pass


class DatabaseOperationError(CompressedDatabaseError):
    """数据库操作错误."""
    pass


@dataclass
class DatabaseConfig:
    """数据库配置.

    Attributes:
        compression_level: ZSTD 压缩级别 (1-22)
        max_workers: 线程池最大工作线程数
        pool_size: 连接池大小
        enable_wal: 启用 WAL 模式以支持并发读
        auto_vacuum: 自动清理模式
        cache_size: SQLite 缓存大小（页）
        mmap_size: 内存映射大小（字节）
    """

    compression_level: int = 5
    max_workers: int = 4
    pool_size: int = 4
    enable_wal: bool = True
    auto_vacuum: bool = True
    cache_size: int = 2000  # 约 8MB
    mmap_size: int = 256 * 1024 * 1024  # 256MB


class ConnectionPool:
    """SQLite 连接池.

    提供线程安全的连接池管理，支持并发读取.

    Attributes:
        db_path: 数据库文件路径
        pool_size: 连接池大小
        enable_wal: 是否启用 WAL 模式
    """

    def __init__(
        self,
        db_path: Path,
        pool_size: int = 4,
        enable_wal: bool = True,
        cache_size: int = 2000,
        mmap_size: int = 256 * 1024 * 1024,
    ) -> None:
        """初始化连接池.

        Args:
            db_path: 数据库文件路径
            pool_size: 连接池大小
            enable_wal: 是否启用 WAL 模式
            cache_size: SQLite 缓存大小
            mmap_size: 内存映射大小
        """
        self.db_path = db_path
        self.pool_size = pool_size
        self.enable_wal = enable_wal
        self.cache_size = cache_size
        self.mmap_size = mmap_size

        self._pool: list[sqlite3.Connection] = []
        self._lock = threading.Lock()
        self._initialized = False

    def initialize(self) -> None:
        """初始化连接池."""
        if self._initialized:
            return

        with self._lock:
            if self._initialized:
                return

            for i in range(self.pool_size):
                conn = self._create_connection()
                self._pool.append(conn)

            self._initialized = True
            logger.debug(f"连接池初始化完成，池大小：{self.pool_size}")

    def _create_connection(self) -> sqlite3.Connection:
        """创建单个数据库连接.

        Returns:
            SQLite 连接对象
        """
        conn = sqlite3.connect(
            str(self.db_path),
            check_same_thread=False,
            isolation_level=None,  # 自动提交模式
        )
        conn.row_factory = sqlite3.Row

        # 配置 SQLite 参数
        cursor = conn.cursor()

        # 启用 WAL 模式以支持并发读
        if self.enable_wal:
            cursor.execute("PRAGMA journal_mode=WAL")

        # 设置缓存大小
        cursor.execute(f"PRAGMA cache_size=-{self.cache_size}")

        # 设置内存映射大小
        cursor.execute(f"PRAGMA mmap_size={self.mmap_size}")

        # 启用外键约束
        cursor.execute("PRAGMA foreign_keys=ON")

        # 同步模式：NORMAL 在性能和安全性之间取得平衡
        cursor.execute("PRAGMA synchronous=NORMAL")

        conn.commit()
        cursor.close()

        return conn

    def get_connection(self) -> sqlite3.Connection:
        """从连接池获取连接.

        Returns:
            SQLite 连接对象

        Raises:
            DatabaseConnectionError: 无法获取连接
        """
        if not self._initialized:
            self.initialize()

        with self._lock:
            if self._pool:
                return self._pool.pop()
            # 池为空时创建新连接
            return self._create_connection()

    def return_connection(self, conn: sqlite3.Connection) -> None:
        """将连接返回到连接池.

        Args:
            conn: 要返回的连接
        """
        with self._lock:
            if len(self._pool) < self.pool_size:
                try:
                    # 检查连接是否有效
                    conn.execute("SELECT 1")
                    self._pool.append(conn)
                except sqlite3.Error:
                    conn.close()
            else:
                conn.close()

    def close_all(self) -> None:
        """关闭所有连接."""
        with self._lock:
            for conn in self._pool:
                try:
                    conn.close()
                except sqlite3.Error:
                    pass
            self._pool.clear()
            self._initialized = False
            logger.debug("连接池已关闭")


class CompressedDatabase:
    """ZSTD 压缩的 SQLite 数据库.

    提供透明的数据压缩存储和检索功能，适用于缓存搜索结果、
    索引数据等需要频繁读写且占用空间较大的场景.

    Attributes:
        db_path: 数据库文件路径
        config: 数据库配置
        stats: 压缩统计信息

    Example:
        ```python
        db = CompressedDatabase(
            "cache.db",
            compression_level=5,
            enable_wal=True
        )
        await db.initialize()
        await db.store_search_results("query123", results)
        ```

    Note:
        - 默认压缩级别为 5，在速度和压缩率之间取得平衡
        - 对于频繁写入的场景，建议使用较低的压缩级别 (1-3)
        - 对于归档数据，可以使用较高的压缩级别 (10+)
        - 启用 WAL 模式可支持并发读取
    """

    DEFAULT_COMPRESSION_LEVEL = 5
    MAX_COMPRESSION_LEVEL = 22
    MIN_COMPRESSION_LEVEL = 1

    def __init__(
        self,
        db_path: str | Path,
        compression_level: int = DEFAULT_COMPRESSION_LEVEL,
        use_threading: bool = True,
        max_workers: int = 4,
        pool_size: int = 4,
        enable_wal: bool = True,
        auto_cleanup: bool = True,
        cleanup_interval: int = 300,
    ) -> None:
        """初始化压缩数据库.

        Args:
            db_path: 数据库文件路径
            compression_level: ZSTD 压缩级别 (1-22)，默认 5
            use_threading: 是否使用线程池执行数据库操作
            max_workers: 线程池最大工作线程数
            pool_size: 连接池大小
            enable_wal: 启用 WAL 模式以支持并发读
            auto_cleanup: 启用自动清理
            cleanup_interval: 自动清理间隔（秒）

        Raises:
            ValueError: 压缩级别超出有效范围
        """
        self.db_path = Path(db_path)
        self.config = DatabaseConfig(
            compression_level=self._validate_compression_level(compression_level),
            max_workers=max_workers,
            pool_size=pool_size,
            enable_wal=enable_wal,
        )
        self.use_threading = use_threading
        self.auto_cleanup = auto_cleanup
        self.cleanup_interval = cleanup_interval

        # 初始化 ZSTD 压缩器
        self._compressor = zstd.ZstdCompressor(level=self.config.compression_level)
        self._decompressor = zstd.ZstdDecompressor()

        # 连接池
        self._pool: Optional[ConnectionPool] = None

        # 统计信息
        self._stats = CompressionStats()
        self._db_stats = CompressionStats()

        # 线程池执行器
        self._executor: Optional[ThreadPoolExecutor] = None
        if use_threading:
            self._executor = ThreadPoolExecutor(max_workers=max_workers)

        # 锁
        self._stats_lock = asyncio.Lock()
        self._init_lock = asyncio.Lock()

        # 自动清理任务
        self._cleanup_task: Optional[asyncio.Task] = None
        self._running = False

        # 性能基准（用于计算性能影响）
        self._read_benchmark_ms: float = 0.0
        self._write_benchmark_ms: float = 0.0

    def _validate_compression_level(self, level: int) -> int:
        """验证压缩级别.

        Args:
            level: 压缩级别

        Returns:
            有效的压缩级别

        Raises:
            ValueError: 级别超出范围
        """
        if not self.MIN_COMPRESSION_LEVEL <= level <= self.MAX_COMPRESSION_LEVEL:
            raise ValueError(
                f"压缩级别必须在 {self.MIN_COMPRESSION_LEVEL} 到 {self.MAX_COMPRESSION_LEVEL} 之间，"
                f"当前值：{level}"
            )
        return level

    async def initialize(self) -> None:
        """初始化数据库连接和表结构.

        创建必要的表结构用于存储压缩数据.

        Raises:
            DatabaseConnectionError: 数据库初始化失败
        """
        async with self._init_lock:
            if self._pool is not None:
                return  # 已初始化

            try:
                # 确保目录存在
                self.db_path.parent.mkdir(parents=True, exist_ok=True)

                # 初始化连接池
                self._pool = ConnectionPool(
                    db_path=self.db_path,
                    pool_size=self.config.pool_size,
                    enable_wal=self.config.enable_wal,
                    cache_size=self.config.cache_size,
                    mmap_size=self.config.mmap_size,
                )
                self._pool.initialize()

                # 创建表结构
                await self._create_tables()

                # 启动自动清理任务
                if self.auto_cleanup:
                    self._running = True
                    self._cleanup_task = asyncio.create_task(self._auto_cleanup_loop())

                logger.info(f"数据库初始化完成：{self.db_path}")

            except sqlite3.Error as e:
                logger.error(f"数据库初始化失败：{e}")
                raise DatabaseConnectionError(f"初始化失败：{e}") from e
            except Exception as e:
                logger.error(f"数据库初始化异常：{e}")
                raise DatabaseConnectionError(f"初始化异常：{e}") from e

    async def _create_tables(self) -> None:
        """创建数据库表结构."""
        conn = self._get_connection()
        try:
            cursor = conn.cursor()

            # 搜索结果缓存表
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS search_cache (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    query_hash TEXT UNIQUE NOT NULL,
                    query_pattern TEXT NOT NULL,
                    search_path TEXT NOT NULL,
                    compressed_data BLOB NOT NULL,
                    original_size INTEGER NOT NULL,
                    created_at REAL NOT NULL,
                    expires_at REAL NOT NULL,
                    access_count INTEGER DEFAULT 0,
                    last_accessed REAL,
                    compression_ratio REAL,
                    compress_time_ms REAL
                )
            """)

            # 文件索引表
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS file_index (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    file_path TEXT UNIQUE NOT NULL,
                    file_hash TEXT NOT NULL,
                    file_size INTEGER NOT NULL,
                    compressed_content BLOB,
                    indexed_at REAL NOT NULL,
                    modified_at REAL,
                    compression_ratio REAL
                )
            """)

            # 元数据表
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS metadata (
                    key TEXT PRIMARY KEY,
                    compressed_value BLOB NOT NULL,
                    original_size INTEGER,
                    updated_at REAL NOT NULL
                )
            """)

            # 性能基准表
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS performance_benchmark (
                    id INTEGER PRIMARY KEY,
                    read_time_ms REAL,
                    write_time_ms REAL,
                    recorded_at REAL NOT NULL
                )
            """)

            # 创建索引
            cursor.execute(
                "CREATE INDEX IF NOT EXISTS idx_search_cache_query ON search_cache(query_hash)"
            )
            cursor.execute(
                "CREATE INDEX IF NOT EXISTS idx_search_cache_expires ON search_cache(expires_at)"
            )
            cursor.execute(
                "CREATE INDEX IF NOT EXISTS idx_search_cache_pattern ON search_cache(query_pattern)"
            )
            cursor.execute(
                "CREATE INDEX IF NOT EXISTS idx_file_index_hash ON file_index(file_hash)"
            )
            cursor.execute(
                "CREATE INDEX IF NOT EXISTS idx_file_index_path ON file_index(file_path)"
            )

            conn.commit()
            logger.debug("数据库表结构创建完成")

        except sqlite3.Error as e:
            logger.error(f"创建表结构失败：{e}")
            raise DatabaseOperationError(f"创建表失败：{e}") from e
        finally:
            self._return_connection(conn)

    def _get_connection(self) -> sqlite3.Connection:
        """获取数据库连接.

        Returns:
            SQLite 连接对象

        Raises:
            DatabaseConnectionError: 无法获取连接
        """
        if self._pool is None:
            raise DatabaseConnectionError("数据库未初始化")
        return self._pool.get_connection()

    def _return_connection(self, conn: sqlite3.Connection) -> None:
        """返回数据库连接到连接池.

        Args:
            conn: 要返回的连接
        """
        if self._pool is not None:
            self._pool.return_connection(conn)

    async def close(self) -> None:
        """关闭数据库连接并释放资源."""
        self._running = False

        # 取消清理任务
        if self._cleanup_task:
            self._cleanup_task.cancel()
            try:
                await self._cleanup_task
            except asyncio.CancelledError:
                pass

        # 关闭连接池
        if self._pool:
            self._pool.close_all()
            self._pool = None

        # 关闭线程池
        if self._executor:
            self._executor.shutdown(wait=True)
            self._executor = None

        logger.info("数据库已关闭")

    async def __aenter__(self) -> CompressedDatabase:
        """异步上下文管理器入口."""
        await self.initialize()
        return self

    async def __aexit__(self, exc_type: Any, exc_val: Any, exc_tb: Any) -> None:
        """异步上下文管理器出口."""
        await self.close()

    def _compress(self, data: bytes) -> tuple[bytes, float]:
        """压缩数据.

        Args:
            data: 原始数据

        Returns:
            (压缩后的数据，压缩耗时 ms)

        Raises:
            CompressionError: 压缩失败
        """
        start_time = time.perf_counter()
        try:
            compressed = self._compressor.compress(data)
            elapsed = (time.perf_counter() - start_time) * 1000
            return compressed, elapsed
        except zstd.ZstdError as e:
            logger.error(f"压缩失败：{e}")
            raise CompressionError(f"压缩失败：{e}") from e

    def _decompress(self, data: bytes) -> tuple[bytes, float]:
        """解压缩数据.

        Args:
            data: 压缩数据

        Returns:
            (原始数据，解压缩耗时 ms)

        Raises:
            CompressionError: 解压缩失败
        """
        start_time = time.perf_counter()
        try:
            decompressed = self._decompressor.decompress(data)
            elapsed = (time.perf_counter() - start_time) * 1000
            return decompressed, elapsed
        except zstd.ZstdError as e:
            logger.error(f"解压缩失败：{e}")
            raise CompressionError(f"解压缩失败：{e}") from e

    async def _run_in_executor(self, func: Callable, *args: Any) -> Any:
        """在线程池中运行函数.

        Args:
            func: 要执行的函数
            *args: 函数参数

        Returns:
            函数返回值
        """
        if self.use_threading and self._executor:
            return await asyncio.get_event_loop().run_in_executor(
                self._executor, func, *args
            )
        return func(*args)

    async def store_search_results(
        self,
        query_hash: str,
        pattern: str,
        search_path: str,
        results: list[SearchResult],
        ttl_seconds: int = 3600,
    ) -> CompressionStats:
        """存储搜索结果.

        Args:
            query_hash: 查询哈希值（用于唯一标识）
            pattern: 搜索模式
            search_path: 搜索路径
            results: 搜索结果列表
            ttl_seconds: 缓存生存时间（秒）

        Returns:
            压缩统计信息

        Raises:
            DatabaseOperationError: 存储失败
            CompressionError: 压缩失败
        """
        if self._pool is None:
            raise DatabaseOperationError("数据库未初始化")

        # 序列化结果
        results_data = json.dumps([r.to_dict() for r in results]).encode("utf-8")

        # 压缩数据
        compressed_data, compress_time = self._compress(results_data)

        now = time.time()
        expires_at = now + ttl_seconds
        compression_ratio = len(compressed_data) / len(results_data) if results_data else 0

        def _store() -> CompressionStats:
            conn = self._get_connection()
            try:
                cursor = conn.cursor()
                cursor.execute(
                    """
                    INSERT OR REPLACE INTO search_cache
                    (query_hash, query_pattern, search_path, compressed_data,
                     original_size, created_at, expires_at, access_count,
                     last_accessed, compression_ratio, compress_time_ms)
                    VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?)
                """,
                    (
                        query_hash,
                        pattern,
                        search_path,
                        compressed_data,
                        len(results_data),
                        now,
                        expires_at,
                        now,
                        compression_ratio,
                        compress_time,
                    ),
                )
                conn.commit()

                # 更新统计
                stats = CompressionStats(
                    original_size=len(results_data),
                    compressed_size=len(compressed_data),
                    compress_time_ms=compress_time,
                    operation_count=1,
                )
                if stats.original_size > 0:
                    stats.compression_ratio = stats.compressed_size / stats.original_size
                return stats

            except sqlite3.Error as e:
                logger.error(f"存储搜索结果失败：{e}")
                raise DatabaseOperationError(f"存储失败：{e}") from e
            finally:
                self._return_connection(conn)

        stats = await self._run_in_executor(_store)

        # 更新总体统计
        async with self._stats_lock:
            self._stats.original_size += stats.original_size
            self._stats.compressed_size += stats.compressed_size
            self._stats.compress_time_ms += stats.compress_time_ms
            self._stats.operation_count += 1
            if self._stats.original_size > 0:
                self._stats.compression_ratio = (
                    self._stats.compressed_size / self._stats.original_size
                )

        logger.debug(
            f"存储搜索结果：hash={query_hash}, "
            f"原始={stats.original_size}B, 压缩={stats.compressed_size}B, "
            f"压缩比={stats.compression_ratio_display}"
        )

        return stats

    async def retrieve_search_results(
        self, query_hash: str
    ) -> tuple[list[SearchResult] | None, CompressionStats]:
        """检索搜索结果.

        Args:
            query_hash: 查询哈希值

        Returns:
            (搜索结果列表，压缩统计信息)，如果不存在或已过期则返回 (None, stats)

        Raises:
            CompressionError: 解压缩失败
            DatabaseOperationError: 检索失败
        """
        if self._pool is None:
            raise DatabaseOperationError("数据库未初始化")

        stats = CompressionStats()

        def _retrieve() -> tuple[list[dict] | None, float]:
            conn = self._get_connection()
            try:
                cursor = conn.cursor()
                cursor.execute(
                    """
                    SELECT compressed_data, original_size FROM search_cache
                    WHERE query_hash = ? AND expires_at > ?
                """,
                    (query_hash, time.time()),
                )
                row = cursor.fetchone()

                if row is None:
                    return None, 0.0

                # 更新访问统计
                cursor.execute(
                    """
                    UPDATE search_cache
                    SET access_count = access_count + 1, last_accessed = ?
                    WHERE query_hash = ?
                """,
                    (time.time(), query_hash),
                )
                conn.commit()

                return row[0], row[1]

            except sqlite3.Error as e:
                logger.error(f"检索搜索结果失败：{e}")
                raise DatabaseOperationError(f"检索失败：{e}") from e
            finally:
                self._return_connection(conn)

        row_data = await self._run_in_executor(_retrieve)

        if row_data[0] is None:
            return None, stats

        compressed_data, original_size = row_data

        # 解压缩
        decompressed, decompress_time = self._decompress(compressed_data)

        stats.decompress_time_ms = decompress_time
        stats.original_size = original_size
        stats.compressed_size = len(compressed_data)
        stats.operation_count = 1
        if stats.original_size > 0:
            stats.compression_ratio = stats.compressed_size / stats.original_size

        # 解析 JSON
        try:
            results_data = json.loads(decompressed.decode("utf-8"))
            results = [
                SearchResult(
                    file_path=r["file_path"],
                    line_number=r["line_number"],
                    content=r["content"],
                    context_before=r.get("context_before", []),
                    context_after=r.get("context_after", []),
                    match_start=r.get("match_start"),
                    match_end=r.get("match_end"),
                    metadata=r.get("metadata", {}),
                )
                for r in results_data
            ]

            # 更新总体统计
            async with self._stats_lock:
                self._stats.decompress_time_ms += decompress_time
                self._stats.operation_count += 1

            logger.debug(
                f"检索搜索结果：hash={query_hash}, "
                f"解压缩耗时={decompress_time:.2f}ms"
            )

            return results, stats

        except (json.JSONDecodeError, UnicodeDecodeError) as e:
            logger.error(f"解析搜索结果失败：{e}")
            raise CompressionError(f"解析失败：{e}") from e

    async def store_metadata(self, key: str, value: Any) -> CompressionStats:
        """存储元数据.

        Args:
            key: 元数据键
            value: 元数据值

        Returns:
            压缩统计信息

        Raises:
            DatabaseOperationError: 存储失败
        """
        if self._pool is None:
            raise DatabaseOperationError("数据库未初始化")

        # 序列化
        data = json.dumps(value).encode("utf-8")
        compressed, compress_time = self._compress(data)

        now = time.time()

        def _store() -> CompressionStats:
            conn = self._get_connection()
            try:
                cursor = conn.cursor()
                cursor.execute(
                    """
                    INSERT OR REPLACE INTO metadata
                    (key, compressed_value, original_size, updated_at)
                    VALUES (?, ?, ?, ?)
                """,
                    (key, compressed, len(data), now),
                )
                conn.commit()

                stats = CompressionStats(
                    original_size=len(data),
                    compressed_size=len(compressed),
                    compress_time_ms=compress_time,
                    operation_count=1,
                )
                if stats.original_size > 0:
                    stats.compression_ratio = stats.compressed_size / stats.original_size
                return stats

            except sqlite3.Error as e:
                logger.error(f"存储元数据失败：{e}")
                raise DatabaseOperationError(f"存储失败：{e}") from e
            finally:
                self._return_connection(conn)

        stats = await self._run_in_executor(_store)

        async with self._stats_lock:
            self._stats.original_size += stats.original_size
            self._stats.compressed_size += stats.compressed_size
            self._stats.compress_time_ms += stats.compress_time_ms
            self._stats.operation_count += 1
            if self._stats.original_size > 0:
                self._stats.compression_ratio = (
                    self._stats.compressed_size / self._stats.original_size
                )

        return stats

    async def retrieve_metadata(self, key: str) -> tuple[Any | None, CompressionStats]:
        """检索元数据.

        Args:
            key: 元数据键

        Returns:
            (元数据值，压缩统计信息)

        Raises:
            CompressionError: 解压缩失败
        """
        if self._pool is None:
            raise DatabaseOperationError("数据库未初始化")

        stats = CompressionStats()

        def _retrieve() -> tuple[bytes | None, int]:
            conn = self._get_connection()
            try:
                cursor = conn.cursor()
                cursor.execute(
                    "SELECT compressed_value, original_size FROM metadata WHERE key = ?",
                    (key,),
                )
                row = cursor.fetchone()
                return (row[0], row[1]) if row else (None, 0)

            except sqlite3.Error as e:
                logger.error(f"检索元数据失败：{e}")
                raise DatabaseOperationError(f"检索失败：{e}") from e
            finally:
                self._return_connection(conn)

        row_data = await self._run_in_executor(_retrieve)

        if row_data[0] is None:
            return None, stats

        compressed_data, original_size = row_data
        decompressed, decompress_time = self._decompress(compressed_data)

        stats.decompress_time_ms = decompress_time
        stats.original_size = original_size
        stats.compressed_size = len(compressed_data)
        stats.operation_count = 1
        if stats.original_size > 0:
            stats.compression_ratio = stats.compressed_size / stats.original_size

        try:
            value = json.loads(decompressed.decode("utf-8"))
            async with self._stats_lock:
                self._stats.decompress_time_ms += decompress_time
                self._stats.operation_count += 1
            return value, stats

        except (json.JSONDecodeError, UnicodeDecodeError) as e:
            logger.error(f"解析元数据失败：{e}")
            raise CompressionError(f"解析失败：{e}") from e

    async def cleanup_expired(self) -> int:
        """清理过期的缓存数据.

        Returns:
            清理的记录数

        Raises:
            DatabaseOperationError: 清理失败
        """
        if self._pool is None:
            raise DatabaseOperationError("数据库未初始化")

        def _cleanup() -> int:
            conn = self._get_connection()
            try:
                cursor = conn.cursor()

                # 统计过期记录数
                cursor.execute(
                    "SELECT COUNT(*) FROM search_cache WHERE expires_at <= ?",
                    (time.time(),),
                )
                count = cursor.fetchone()[0]

                if count > 0:
                    # 删除过期记录
                    cursor.execute(
                        "DELETE FROM search_cache WHERE expires_at <= ?",
                        (time.time(),),
                    )
                    conn.commit()

                    # 执行 VACUUM 回收空间
                    if self.config.auto_vacuum:
                        cursor.execute("VACUUM")
                        conn.commit()

                    logger.info(f"清理过期数据：{count} 条记录")

                return count

            except sqlite3.Error as e:
                logger.error(f"清理过期数据失败：{e}")
                raise DatabaseOperationError(f"清理失败：{e}") from e
            finally:
                self._return_connection(conn)

        return await self._run_in_executor(_cleanup)

    async def _auto_cleanup_loop(self) -> None:
        """自动清理循环."""
        while self._running:
            try:
                await asyncio.sleep(self.cleanup_interval)
                if self._running:
                    await self.cleanup_expired()
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"自动清理失败：{e}")

    async def get_stats(self) -> CompressionStats:
        """获取压缩统计信息.

        Returns:
            压缩统计数据
        """
        if self._pool is None:
            raise DatabaseOperationError("数据库未初始化")

        def _get_db_stats() -> dict[str, Any]:
            conn = self._get_connection()
            try:
                cursor = conn.cursor()

                # 缓存条目统计
                cursor.execute("SELECT COUNT(*) FROM search_cache")
                cache_count = cursor.fetchone()[0]

                # 大小统计
                cursor.execute("SELECT SUM(original_size) FROM search_cache")
                total_original = cursor.fetchone()[0] or 0

                cursor.execute("SELECT SUM(LENGTH(compressed_data)) FROM search_cache")
                total_compressed = cursor.fetchone()[0] or 0

                # 平均压缩比
                cursor.execute(
                    "SELECT AVG(compression_ratio) FROM search_cache WHERE compression_ratio > 0"
                )
                avg_ratio = cursor.fetchone()[0] or 0

                # 文件索引统计
                cursor.execute("SELECT COUNT(*) FROM file_index")
                file_count = cursor.fetchone()[0]

                return {
                    "cache_entries": cache_count,
                    "file_entries": file_count,
                    "total_original_size": total_original,
                    "total_compressed_size": total_compressed,
                    "avg_compression_ratio": avg_ratio,
                }

            except sqlite3.Error as e:
                logger.error(f"获取统计信息失败：{e}")
                raise DatabaseOperationError(f"获取统计失败：{e}") from e
            finally:
                self._return_connection(conn)

        db_stats = await self._run_in_executor(_get_db_stats)

        # 合并统计信息
        async with self._stats_lock:
            self._db_stats.original_size = db_stats.get("total_original_size", 0)
            self._db_stats.compressed_size = db_stats.get("total_compressed_size", 0)
            if self._db_stats.original_size > 0:
                self._db_stats.compression_ratio = (
                    self._db_stats.compressed_size / self._db_stats.original_size
                )

            # 返回合并后的统计
            combined = CompressionStats(
                original_size=self._db_stats.original_size,
                compressed_size=self._db_stats.compressed_size,
                compress_time_ms=self._stats.compress_time_ms,
                decompress_time_ms=self._stats.decompress_time_ms,
                operation_count=self._stats.operation_count,
            )
            if combined.original_size > 0:
                combined.compression_ratio = (
                    combined.compressed_size / combined.original_size
                )

            return combined

    async def get_table_stats(self, table_name: str) -> dict[str, Any]:
        """获取指定表的统计信息.

        Args:
            table_name: 表名

        Returns:
            表统计信息字典
        """
        if self._pool is None:
            raise DatabaseOperationError("数据库未初始化")

        def _get_stats() -> dict[str, Any]:
            conn = self._get_connection()
            try:
                cursor = conn.cursor()

                # 行数
                cursor.execute(f"SELECT COUNT(*) FROM {table_name}")
                row_count = cursor.fetchone()[0]

                # 大小统计
                cursor.execute(
                    f"SELECT SUM(original_size), SUM(LENGTH(compressed_data)), AVG(compression_ratio) FROM {table_name}"
                )
                row = cursor.fetchone()
                total_original = row[0] or 0
                total_compressed = row[1] or 0
                avg_ratio = row[2] or 0

                return {
                    "row_count": row_count,
                    "total_original_size": total_original,
                    "total_compressed_size": total_compressed,
                    "avg_compression_ratio": avg_ratio,
                    "compression_ratio_display": (
                        f"{1/avg_ratio:.1f}:1" if avg_ratio > 0 else "N/A"
                    ),
                }

            except sqlite3.Error as e:
                logger.error(f"获取表统计失败：{e}")
                return {}
            finally:
                self._return_connection(conn)

        return await self._run_in_executor(_get_stats)

    async def execute(
        self, query: str, params: tuple[Any, ...] = ()
    ) -> list[sqlite3.Row]:
        """执行 SQL 查询.

        Args:
            query: SQL 查询语句
            params: 查询参数

        Returns:
            查询结果列表

        Raises:
            DatabaseOperationError: 执行失败
        """
        if self._pool is None:
            raise DatabaseOperationError("数据库未初始化")

        def _execute() -> list[sqlite3.Row]:
            conn = self._get_connection()
            try:
                cursor = conn.cursor()
                cursor.execute(query, params)
                return cursor.fetchall()

            except sqlite3.Error as e:
                logger.error(f"执行 SQL 失败：{e}")
                raise DatabaseOperationError(f"执行失败：{e}") from e
            finally:
                self._return_connection(conn)

        return await self._run_in_executor(_execute)

    async def run_benchmark(self, iterations: int = 100) -> dict[str, float]:
        """运行性能基准测试.

        Args:
            iterations: 测试迭代次数

        Returns:
            基准测试结果
        """
        # 准备测试数据
        test_data = b"x" * 10000  # 10KB 数据

        # 测试压缩性能
        compress_times = []
        for _ in range(iterations):
            start = time.perf_counter()
            self._compressor.compress(test_data)
            compress_times.append((time.perf_counter() - start) * 1000)

        # 测试解压缩性能
        compressed = self._compressor.compress(test_data)
        decompress_times = []
        for _ in range(iterations):
            start = time.perf_counter()
            self._decompressor.decompress(compressed)
            decompress_times.append((time.perf_counter() - start) * 1000)

        # 计算平均值
        avg_compress = sum(compress_times) / len(compress_times)
        avg_decompress = sum(decompress_times) / len(decompress_times)

        # 计算压缩比
        compression_ratio = len(compressed) / len(test_data)

        result = {
            "avg_compress_time_ms": avg_compress,
            "avg_decompress_time_ms": avg_decompress,
            "compression_ratio": compression_ratio,
            "compression_ratio_display": f"{1/compression_ratio:.1f}:1" if compression_ratio > 0 else "N/A",
        }

        logger.info(f"性能基准测试结果：{result}")
        return result

    async def estimate_performance_impact(self) -> dict[str, float]:
        """估算压缩对性能的影响.

        Returns:
            性能影响估算结果
        """
        # 运行基准测试
        benchmark = await self.run_benchmark(50)

        # 估算无压缩的读写时间（假设压缩/解压缩是额外开销）
        read_overhead = benchmark["avg_decompress_time_ms"]
        write_overhead = benchmark["avg_compress_time_ms"]

        # 假设基础数据库操作时间
        base_read_time = 1.0  # 1ms 基础读取时间
        base_write_time = 2.0  # 2ms 基础写入时间

        # 计算性能影响百分比
        read_impact = (read_overhead / (base_read_time + read_overhead)) * 100
        write_impact = (write_overhead / (base_write_time + write_overhead)) * 100

        result = {
            "read_overhead_ms": read_overhead,
            "write_overhead_ms": write_overhead,
            "read_impact_percent": read_impact,
            "write_impact_percent": write_impact,
            "meets_read_target": read_impact < 15,
            "meets_write_target": write_impact < 25,
        }

        logger.info(f"性能影响估算：{result}")
        return result

    async def vacuum(self) -> None:
        """执行 VACUUM 回收数据库空间."""
        if self._pool is None:
            raise DatabaseOperationError("数据库未初始化")

        def _vacuum() -> None:
            conn = self._get_connection()
            try:
                cursor = conn.cursor()
                cursor.execute("VACUUM")
                conn.commit()
                logger.info("数据库 VACUUM 完成")

            except sqlite3.Error as e:
                logger.error(f"VACUUM 失败：{e}")
                raise DatabaseOperationError(f"VACUUM 失败：{e}") from e
            finally:
                self._return_connection(conn)

        await self._run_in_executor(_vacuum)

    async def get_compression_report(self) -> dict[str, Any]:
        """获取压缩报告.

        Returns:
            压缩报告字典
        """
        stats = await self.get_stats()
        search_stats = await self.get_table_stats("search_cache")
        file_stats = await self.get_table_stats("file_index")
        performance = await self.estimate_performance_impact()

        report = {
            "overall": stats.to_dict(),
            "search_cache": search_stats,
            "file_index": file_stats,
            "performance": performance,
            "targets": {
                "compression_ratio_target": "5:1",
                "read_impact_target": "<15%",
                "write_impact_target": "<25%",
            },
            "meets_targets": {
                "compression_ratio": stats.compression_ratio <= 0.2,  # 5:1 = 0.2
                "read_impact": performance["meets_read_target"],
                "write_impact": performance["meets_write_target"],
            },
        }

        return report


@asynccontextmanager
async def compressed_database_context(
    db_path: str | Path,
    compression_level: int = 5,
    **kwargs: Any,
) -> AsyncIterator[CompressedDatabase]:
    """创建压缩数据库的异步上下文管理器.

    Args:
        db_path: 数据库文件路径
        compression_level: ZSTD 压缩级别
        **kwargs: 其他配置参数

    Yields:
        CompressedDatabase 实例

    Example:
        ```python
        async with compressed_database_context("cache.db") as db:
            await db.store_search_results("hash", "pattern", "/path", results)
        ```
    """
    db = CompressedDatabase(db_path, compression_level=compression_level, **kwargs)
    try:
        await db.initialize()
        yield db
    finally:
        await db.close()


def compute_query_hash(query: str, path: str, options: dict[str, Any] | None = None) -> str:
    """计算查询哈希.

    Args:
        query: 搜索查询
        path: 搜索路径
        options: 额外选项

    Returns:
        SHA256 哈希值（16 字符）
    """
    data = f"{query}:{path}:{json.dumps(options or {}, sort_keys=True)}"
    return hashlib.sha256(data.encode("utf-8")).hexdigest()[:16]
