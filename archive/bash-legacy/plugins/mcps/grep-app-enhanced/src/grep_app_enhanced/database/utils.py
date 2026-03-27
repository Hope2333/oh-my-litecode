"""
Database Utils - 数据库工具函数和辅助类.

本模块提供数据库相关的工具函数和辅助类，包括：
- 查询哈希计算
- 数据序列化
- 性能分析
- 内存管理
- 错误处理

Author:
    Oh My LiteCode Team
"""

from __future__ import annotations

import asyncio
import functools
import hashlib
import json
import logging
import os
import sys
import time
import tracemalloc
from contextlib import asynccontextmanager, contextmanager
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, AsyncGenerator, Callable, Generator, Generic, Optional, TypeVar

import zstandard as zstd

logger = logging.getLogger(__name__)

if not logger.handlers:
    handler = logging.StreamHandler(sys.stdout)
    handler.setLevel(logging.DEBUG)
    formatter = logging.Formatter(
        "%(asctime)s - %(name)s - %(levelname)s - %(message)s"
    )
    handler.setFormatter(formatter)
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)

T = TypeVar("T")
R = TypeVar("R")


# =============================================================================
# 哈希工具
# =============================================================================


def compute_hash(data: str | bytes, algorithm: str = "sha256", length: int = 16) -> str:
    """计算数据的哈希值.

    Args:
        data: 输入数据
        algorithm: 哈希算法 (md5, sha1, sha256, sha512)
        length: 返回哈希值的长度

    Returns:
        哈希字符串

    Raises:
        ValueError: 不支持的算法
    """
    if isinstance(data, str):
        data = data.encode("utf-8")

    algorithms = {
        "md5": hashlib.md5,
        "sha1": hashlib.sha1,
        "sha256": hashlib.sha256,
        "sha512": hashlib.sha512,
    }

    if algorithm not in algorithms:
        raise ValueError(f"不支持的哈希算法：{algorithm}")

    hash_obj = algorithms[algorithm](data)
    return hash_obj.hexdigest()[:length]


def compute_query_hash(
    query: str,
    path: str,
    options: Optional[dict[str, Any]] = None,
) -> str:
    """计算查询的唯一哈希.

    Args:
        query: 搜索查询
        path: 搜索路径
        options: 额外选项

    Returns:
        16 字符哈希值
    """
    options_str = json.dumps(options or {}, sort_keys=True)
    data = f"{query}:{path}:{options_str}"
    return compute_hash(data, "sha256", 16)


def compute_file_hash(file_path: str | Path, chunk_size: int = 8192) -> str:
    """计算文件的 SHA256 哈希.

    Args:
        file_path: 文件路径
        chunk_size: 读取块大小

    Returns:
        文件哈希值
    """
    sha256 = hashlib.sha256()
    path = Path(file_path)

    with open(path, "rb") as f:
        while chunk := f.read(chunk_size):
            sha256.update(chunk)

    return sha256.hexdigest()


# =============================================================================
# 序列化工具
# =============================================================================


class JsonSerializer:
    """JSON 序列化工具类."""

    @staticmethod
    def serialize(obj: Any, compress: bool = False, level: int = 3) -> bytes:
        """序列化对象.

        Args:
            obj: 要序列化的对象
            compress: 是否压缩
            level: 压缩级别

        Returns:
            序列化后的字节
        """
        data = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        if compress:
            compressor = zstd.ZstdCompressor(level=level)
            return compressor.compress(data)
        return data

    @staticmethod
    def deserialize(data: bytes, compressed: bool = False) -> Any:
        """反序列化对象.

        Args:
            data: 序列化数据
            compressed: 是否已压缩

        Returns:
            反序列化后的对象
        """
        if compressed:
            decompressor = zstd.ZstdDecompressor()
            data = decompressor.decompress(data)
        return json.loads(data.decode("utf-8"))


class BinarySerializer:
    """二进制序列化工具类."""

    @staticmethod
    def pack_int(value: int, size: int = 4) -> bytes:
        """打包整数.

        Args:
            value: 整数值
            size: 字节数

        Returns:
            打包后的字节
        """
        return value.to_bytes(size, byteorder="big", signed=True)

    @staticmethod
    def unpack_int(data: bytes, size: int = 4) -> int:
        """解包整数.

        Args:
            data: 字节数据
            size: 字节数

        Returns:
            解包后的整数
        """
        return int.from_bytes(data[:size], byteorder="big", signed=True)

    @staticmethod
    def pack_string(s: str, encoding: str = "utf-8") -> bytes:
        """打包字符串（带长度前缀）.

        Args:
            s: 字符串
            encoding: 编码

        Returns:
            打包后的字节
        """
        encoded = s.encode(encoding)
        return BinarySerializer.pack_int(len(encoded)) + encoded

    @staticmethod
    def unpack_string(data: bytes, offset: int = 0) -> tuple[str, int]:
        """解包字符串.

        Args:
            data: 字节数据
            offset: 起始偏移

        Returns:
            (字符串，读取的字节数)
        """
        length = BinarySerializer.unpack_int(data[offset:])
        start = offset + 4
        end = start + length
        return data[start:end].decode("utf-8"), 4 + length


# =============================================================================
# 性能分析工具
# =============================================================================


@dataclass
class PerformanceMetrics:
    """性能指标数据类."""

    operation: str
    count: int = 0
    total_time_ms: float = 0.0
    min_time_ms: float = float("inf")
    max_time_ms: float = 0.0
    memory_allocated: int = 0

    @property
    def avg_time_ms(self) -> float:
        """平均耗时."""
        if self.count == 0:
            return 0.0
        return self.total_time_ms / self.count

    @property
    def qps(self) -> float:
        """每秒查询数（基于总时间）."""
        if self.total_time_ms == 0:
            return 0.0
        return self.count / (self.total_time_ms / 1000)

    def to_dict(self) -> dict[str, Any]:
        """转换为字典."""
        return {
            "operation": self.operation,
            "count": self.count,
            "total_time_ms": self.total_time_ms,
            "avg_time_ms": self.avg_time_ms,
            "min_time_ms": self.min_time_ms if self.min_time_ms != float("inf") else 0,
            "max_time_ms": self.max_time_ms,
            "qps": self.qps,
            "memory_allocated": self.memory_allocated,
        }


class PerformanceTracker:
    """性能追踪器.

    用于追踪和记录操作的性能指标.
    """

    def __init__(self) -> None:
        """初始化性能追踪器."""
        self._metrics: dict[str, PerformanceMetrics] = {}
        self._lock = asyncio.Lock()
        self._recording = False

    async def start_recording(self) -> None:
        """开始记录."""
        self._recording = True
        tracemalloc.start()

    async def stop_recording(self) -> None:
        """停止记录."""
        self._recording = False
        current, peak = tracemalloc.get_traced_memory()
        tracemalloc.stop()
        logger.info(f"内存使用：当前={current / 1024 / 1024:.2f}MB, 峰值={peak / 1024 / 1024:.2f}MB")

    @asynccontextmanager
    async def record(self, operation: str) -> AsyncGenerator[None, None]:
        """记录操作的上下文管理器.

        Args:
            operation: 操作名称

        Yields:
            None

        Example:
            ```python
            async with tracker.record("database_query"):
                await db.query("SELECT * FROM table")
            ```
        """
        start_time = time.perf_counter()
        start_memory = tracemalloc.get_traced_memory()[0] if self._recording else 0

        try:
            yield
        finally:
            elapsed = (time.perf_counter() - start_time) * 1000
            memory_used = 0
            if self._recording:
                current_memory = tracemalloc.get_traced_memory()[0]
                memory_used = max(0, current_memory - start_memory)

            async with self._lock:
                if operation not in self._metrics:
                    self._metrics[operation] = PerformanceMetrics(operation=operation)

                metrics = self._metrics[operation]
                metrics.count += 1
                metrics.total_time_ms += elapsed
                metrics.min_time_ms = min(metrics.min_time_ms, elapsed)
                metrics.max_time_ms = max(metrics.max_time_ms, elapsed)
                metrics.memory_allocated += memory_used

    def get_metrics(self, operation: str) -> Optional[PerformanceMetrics]:
        """获取指定操作的指标.

        Args:
            operation: 操作名称

        Returns:
            性能指标
        """
        return self._metrics.get(operation)

    def get_all_metrics(self) -> dict[str, dict[str, Any]]:
        """获取所有操作的指标.

        Returns:
            所有指标字典
        """
        return {op: m.to_dict() for op, m in self._metrics.items()}

    def reset(self) -> None:
        """重置所有指标."""
        self._metrics.clear()

    def print_report(self) -> None:
        """打印性能报告."""
        if not self._metrics:
            print("没有性能数据")
            return

        print("\n" + "=" * 60)
        print("性能报告")
        print("=" * 60)

        for op, metrics in sorted(
            self._metrics.items(),
            key=lambda x: x[1].total_time_ms,
            reverse=True,
        ):
            print(f"\n{metrics.operation}:")
            print(f"  调用次数：{metrics.count}")
            print(f"  总耗时：{metrics.total_time_ms:.2f}ms")
            print(f"  平均耗时：{metrics.avg_time_ms:.2f}ms")
            print(f"  最小耗时：{metrics.min_time_ms:.2f}ms")
            print(f"  最大耗时：{metrics.max_time_ms:.2f}ms")
            print(f"  QPS: {metrics.qps:.2f}")
            if metrics.memory_allocated > 0:
                print(f"  内存分配：{metrics.memory_allocated / 1024:.2f}KB")

        print("=" * 60)


# =============================================================================
# 计时器装饰器
# =============================================================================


def timed(operation_name: Optional[str] = None) -> Callable:
    """计时装饰器.

    Args:
        operation_name: 操作名称

    Returns:
        装饰器函数

    Example:
        ```python
        @timed("database_query")
        async def query_db(sql: str):
            return await db.execute(sql)
        ```
    """

    def decorator(func: Callable[..., T]) -> Callable[..., T]:
        name = operation_name or func.__name__

        @functools.wraps(func)
        async def async_wrapper(*args: Any, **kwargs: Any) -> T:
            start = time.perf_counter()
            try:
                return await func(*args, **kwargs)
            finally:
                elapsed = (time.perf_counter() - start) * 1000
                logger.debug(f"{name} 耗时：{elapsed:.2f}ms")

        @functools.wraps(func)
        def sync_wrapper(*args: Any, **kwargs: Any) -> T:
            start = time.perf_counter()
            try:
                return func(*args, **kwargs)
            finally:
                elapsed = (time.perf_counter() - start) * 1000
                logger.debug(f"{name} 耗时：{elapsed:.2f}ms")

        if asyncio.iscoroutinefunction(func):
            return async_wrapper
        return sync_wrapper

    return decorator


# =============================================================================
# 重试工具
# =============================================================================


@dataclass
class RetryConfig:
    """重试配置."""

    max_retries: int = 3
    base_delay: float = 1.0
    max_delay: float = 60.0
    exponential: bool = True
    exceptions: tuple[type[Exception], ...] = (Exception,)


def retry(config: Optional[RetryConfig] = None) -> Callable:
    """重试装饰器.

    Args:
        config: 重试配置

    Returns:
        装饰器函数

    Example:
        ```python
        @retry(RetryConfig(max_retries=3, base_delay=0.5))
        async def flaky_operation():
            return await do_something()
        ```
    """
    cfg = config or RetryConfig()

    def decorator(func: Callable[..., T]) -> Callable[..., T]:
        @functools.wraps(func)
        async def async_wrapper(*args: Any, **kwargs: Any) -> T:
            last_exception = None
            delay = cfg.base_delay

            for attempt in range(cfg.max_retries + 1):
                try:
                    return await func(*args, **kwargs)
                except cfg.exceptions as e:
                    last_exception = e
                    if attempt < cfg.max_retries:
                        logger.warning(
                            f"{func.__name__} 失败 (尝试 {attempt + 1}/{cfg.max_retries + 1}): {e}"
                        )
                        await asyncio.sleep(delay)
                        if cfg.exponential:
                            delay = min(delay * 2, cfg.max_delay)

            raise last_exception  # type: ignore

        @functools.wraps(func)
        def sync_wrapper(*args: Any, **kwargs: Any) -> T:
            last_exception = None
            delay = cfg.base_delay

            for attempt in range(cfg.max_retries + 1):
                try:
                    return func(*args, **kwargs)
                except cfg.exceptions as e:
                    last_exception = e
                    if attempt < cfg.max_retries:
                        logger.warning(
                            f"{func.__name__} 失败 (尝试 {attempt + 1}/{cfg.max_retries + 1}): {e}"
                        )
                        time.sleep(delay)
                        if cfg.exponential:
                            delay = min(delay * 2, cfg.max_delay)

            raise last_exception  # type: ignore

        if asyncio.iscoroutinefunction(func):
            return async_wrapper
        return sync_wrapper

    return decorator


# =============================================================================
# 内存管理工具
# =============================================================================


class MemoryManager:
    """内存管理工具类."""

    @staticmethod
    def get_process_memory() -> dict[str, int]:
        """获取进程内存使用信息.

        Returns:
            内存使用信息字典
        """
        try:
            import resource

            usage = resource.getrusage(resource.RUSAGE_SELF)
            return {
                "maxrss_kb": usage.ru_maxrss,
                "maxrss_mb": usage.ru_maxrss // 1024,
            }
        except ImportError:
            # Windows/Android fallback
            return {"maxrss_kb": 0, "maxrss_mb": 0}

    @staticmethod
    def get_traced_memory() -> dict[str, int]:
        """获取 tracemalloc 追踪的内存.

        Returns:
            内存信息字典
        """
        try:
            current, peak = tracemalloc.get_traced_memory()
            return {
                "current": current,
                "peak": peak,
                "current_mb": current / 1024 / 1024,
                "peak_mb": peak / 1024 / 1024,
            }
        except Exception:
            return {"current": 0, "peak": 0, "current_mb": 0, "peak_mb": 0}

    @staticmethod
    def format_size(size_bytes: int) -> str:
        """格式化字节大小为可读字符串.

        Args:
            size_bytes: 字节数

        Returns:
            格式化后的字符串
        """
        for unit in ["B", "KB", "MB", "GB", "TB"]:
            if abs(size_bytes) < 1024.0:
                return f"{size_bytes:.2f} {unit}"
            size_bytes /= 1024.0
        return f"{size_bytes:.2f} PB"


# =============================================================================
# 批量处理工具
# =============================================================================


async def batch_process(
    items: list[T],
    processor: Callable[[T], Any],
    batch_size: int = 10,
    concurrency: int = 5,
) -> list[Any]:
    """批量处理项目.

    Args:
        items: 要处理的项目列表
        processor: 处理函数
        batch_size: 批次大小
        concurrency: 并发数

    Returns:
        处理结果列表
    """
    results = []
    semaphore = asyncio.Semaphore(concurrency)

    async def process_with_semaphore(item: T) -> Any:
        async with semaphore:
            if asyncio.iscoroutinefunction(processor):
                return await processor(item)
            return processor(item)

    # 分批处理
    for i in range(0, len(items), batch_size):
        batch = items[i : i + batch_size]
        batch_results = await asyncio.gather(
            *[process_with_semaphore(item) for item in batch],
            return_exceptions=True,
        )
        results.extend(batch_results)

    return results


# =============================================================================
# 限流器
# =============================================================================


class RateLimiter:
    """限流器.

    使用令牌桶算法实现限流.
    """

    def __init__(
        self,
        rate: float,
        capacity: int = 1,
    ) -> None:
        """初始化限流器.

        Args:
            rate: 令牌生成速率（个/秒）
            capacity: 桶容量
        """
        self.rate = rate
        self.capacity = capacity
        self.tokens = float(capacity)
        self.last_update = time.monotonic()
        self._lock = asyncio.Lock()

    async def acquire(self, tokens: int = 1) -> bool:
        """获取令牌.

        Args:
            tokens: 需要的令牌数

        Returns:
            是否获取成功
        """
        async with self._lock:
            now = time.monotonic()
            elapsed = now - self.last_update
            self.tokens = min(self.capacity, self.tokens + elapsed * self.rate)
            self.last_update = now

            if self.tokens >= tokens:
                self.tokens -= tokens
                return True
            return False

    async def wait_for_token(self, tokens: int = 1) -> None:
        """等待直到获取到令牌.

        Args:
            tokens: 需要的令牌数
        """
        while not await self.acquire(tokens):
            wait_time = (tokens - self.tokens) / self.rate
            await asyncio.sleep(wait_time)


# =============================================================================
# 缓存键生成器
# =============================================================================


class CacheKeyGenerator:
    """缓存键生成器.

    提供多种缓存键生成策略.
    """

    @staticmethod
    def simple(key: str) -> str:
        """简单键生成."""
        return key

    @staticmethod
    def prefixed(prefix: str, key: str) -> str:
        """带前缀的键."""
        return f"{prefix}:{key}"

    @staticmethod
    def hashed(key: str, algorithm: str = "sha256", length: int = 16) -> str:
        """哈希键."""
        return compute_hash(key, algorithm, length)

    @staticmethod
    def composite(*parts: Any, separator: str = ":") -> str:
        """组合键.

        Args:
            *parts: 键的各个部分
            separator: 分隔符

        Returns:
            组合后的键
        """
        return separator.join(str(p) for p in parts)

    @staticmethod
    def for_search(
        pattern: str,
        path: str,
        options: Optional[dict[str, Any]] = None,
    ) -> str:
        """为搜索生成缓存键.

        Args:
            pattern: 搜索模式
            path: 搜索路径
            options: 额外选项

        Returns:
            缓存键
        """
        options_str = json.dumps(options or {}, sort_keys=True)
        return f"search:{compute_hash(f'{pattern}:{path}:{options_str}', length=12)}"

    @staticmethod
    def for_file(file_path: str | Path) -> str:
        """为文件生成缓存键.

        Args:
            file_path: 文件路径

        Returns:
            缓存键
        """
        path = Path(file_path)
        return f"file:{compute_hash(str(path.absolute()), length=12)}"


# =============================================================================
# 错误处理工具
# =============================================================================


class DatabaseError(Exception):
    """数据库错误基类."""

    def __init__(
        self,
        message: str,
        original_error: Optional[Exception] = None,
        context: Optional[dict[str, Any]] = None,
    ) -> None:
        super().__init__(message)
        self.original_error = original_error
        self.context = context or {}

    def to_dict(self) -> dict[str, Any]:
        """转换为字典."""
        return {
            "type": self.__class__.__name__,
            "message": str(self),
            "original_error": str(self.original_error) if self.original_error else None,
            "context": self.context,
        }


class CompressionError(DatabaseError):
    """压缩错误."""
    pass


class CacheError(DatabaseError):
    """缓存错误."""
    pass


class SerializationError(DatabaseError):
    """序列化错误."""
    pass


@contextmanager
def handle_errors(
    error_class: type[DatabaseError] = DatabaseError,
    context: Optional[dict[str, Any]] = None,
) -> Generator[None, None, None]:
    """错误处理上下文管理器.

    Args:
        error_class: 错误类型
        context: 错误上下文

    Example:
        ```python
        with handle_errors(CompressionError, {"operation": "compress"}):
            compress_data(data)
        ```
    """
    try:
        yield
    except Exception as e:
        raise error_class(
            message=str(e),
            original_error=e,
            context=context or {},
        ) from e


# =============================================================================
# 数据验证工具
# =============================================================================


def validate_compression_ratio(
    original_size: int,
    compressed_size: int,
    min_ratio: float = 0.1,
    max_ratio: float = 1.0,
) -> bool:
    """验证压缩比是否在合理范围内.

    Args:
        original_size: 原始大小
        compressed_size: 压缩后大小
        min_ratio: 最小允许比率
        max_ratio: 最大允许比率

    Returns:
        是否有效
    """
    if original_size <= 0 or compressed_size < 0:
        return False

    ratio = compressed_size / original_size
    return min_ratio <= ratio <= max_ratio


def validate_cache_entry(entry: Any) -> bool:
    """验证缓存条目是否有效.

    Args:
        entry: 缓存条目

    Returns:
        是否有效
    """
    if not hasattr(entry, "value"):
        return False
    if not hasattr(entry, "expires_at"):
        return False
    if not hasattr(entry, "created_at"):
        return False
    return True


# =============================================================================
# 日志工具
# =============================================================================


class LogContext:
    """日志上下文管理器.

    用于在特定上下文中添加额外的日志信息.
    """

    def __init__(self, **kwargs: Any) -> None:
        """初始化日志上下文.

        Args:
            **kwargs: 额外的上下文信息
        """
        self.context = kwargs
        self.logger = logging.getLogger(self.context.get("logger", __name__))

    def debug(self, message: str, **extra: Any) -> None:
        """记录 debug 日志."""
        ctx = {**self.context, **extra}
        self.logger.debug(f"[{ctx}] {message}")

    def info(self, message: str, **extra: Any) -> None:
        """记录 Info 日志."""
        ctx = {**self.context, **extra}
        self.logger.info(f"[{ctx}] {message}")

    def warning(self, message: str, **extra: Any) -> None:
        """记录 Warning 日志."""
        ctx = {**self.context, **extra}
        self.logger.warning(f"[{ctx}] {message}")

    def error(self, message: str, **extra: Any) -> None:
        """记录 Error 日志."""
        ctx = {**self.context, **extra}
        self.logger.error(f"[{ctx}] {message}")


# =============================================================================
# 导出公共 API
# =============================================================================

__all__ = [
    # 哈希工具
    "compute_hash",
    "compute_query_hash",
    "compute_file_hash",
    # 序列化
    "JsonSerializer",
    "BinarySerializer",
    # 性能分析
    "PerformanceMetrics",
    "PerformanceTracker",
    "timed",
    # 重试
    "RetryConfig",
    "retry",
    # 内存管理
    "MemoryManager",
    # 批量处理
    "batch_process",
    # 限流器
    "RateLimiter",
    # 缓存键
    "CacheKeyGenerator",
    # 错误处理
    "DatabaseError",
    "CompressionError",
    "CacheError",
    "SerializationError",
    "handle_errors",
    # 验证
    "validate_compression_ratio",
    "validate_cache_entry",
    # 日志
    "LogContext",
]
