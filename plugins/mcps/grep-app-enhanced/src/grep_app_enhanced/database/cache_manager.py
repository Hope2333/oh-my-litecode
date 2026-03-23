"""
Cache Manager - 智能缓存管理模块.

本模块提供多层缓存管理功能，支持：
- 内存缓存（LRU 策略）
- 磁盘缓存（压缩存储）
- 缓存预热
- 自动过期清理
- 缓存命中率统计
- 实时监控

Example:
    ```python
    from grep_app_enhanced.database import CacheManager

    cache = CacheManager(
        ttl=3600,
        max_size=1000,
        use_disk_cache=True
    )
    await cache.initialize()
    await cache.set("key", "value")
    value = await cache.get("key")
    ```

Cache Strategy:
    - LRU (Least Recently Used): 最近最少使用优先淘汰
    - TTL (Time To Live): 基于时间的自动过期
    - Size Limit: 基于大小的容量限制
    - LFU (Least Frequently Used): 可选的频率淘汰策略

Monitoring:
    - 实时命中率统计
    - 内存使用监控
    - 缓存条目详情
    - 性能指标追踪

Author:
    Oh My LiteCode Team
"""

from __future__ import annotations

import asyncio
import hashlib
import heapq
import json
import logging
import os
import sys
import time
from collections import OrderedDict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable, Generic, Optional, TypeVar, Union

import zstandard as zstd

T = TypeVar("T")

# 配置日志
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


@dataclass
class CacheEntry(Generic[T]):
    """缓存条目数据类.

    Attributes:
        value: 缓存的值
        created_at: 创建时间戳
        expires_at: 过期时间戳
        access_count: 访问次数
        last_accessed: 最后访问时间
        size_bytes: 数据大小（字节）
        key: 缓存键
        priority: 优先级（用于优先级淘汰）

    Example:
        ```python
        entry = CacheEntry(
            value="data",
            created_at=time.time(),
            expires_at=time.time() + 3600
        )
        ```
    """

    value: T
    created_at: float
    expires_at: float
    access_count: int = 0
    last_accessed: float = 0.0
    size_bytes: int = 0
    key: str = ""
    priority: int = 0  # 越高优先级越高

    def is_expired(self) -> bool:
        """检查是否已过期.

        Returns:
            如果已过期返回 True
        """
        return time.time() > self.expires_at

    def touch(self) -> None:
        """更新访问时间并增加访问计数."""
        self.access_count += 1
        self.last_accessed = time.time()

    def time_until_expiry(self) -> float:
        """获取距离过期的时间（秒）.

        Returns:
            剩余秒数，如果已过期返回 0
        """
        return max(0, self.expires_at - time.time())

    def to_dict(self) -> dict[str, Any]:
        """转换为字典格式."""
        return {
            "value": self.value,
            "created_at": self.created_at,
            "expires_at": self.expires_at,
            "access_count": self.access_count,
            "last_accessed": self.last_accessed,
            "size_bytes": self.size_bytes,
            "key": self.key,
            "priority": self.priority,
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> CacheEntry[T]:
        """从字典创建缓存条目.

        Args:
            data: 包含缓存数据的字典

        Returns:
            CacheEntry 实例
        """
        return cls(
            value=data["value"],
            created_at=data["created_at"],
            expires_at=data["expires_at"],
            access_count=data.get("access_count", 0),
            last_accessed=data.get("last_accessed", 0.0),
            size_bytes=data.get("size_bytes", 0),
            key=data.get("key", ""),
            priority=data.get("priority", 0),
        )

    def __lt__(self, other: CacheEntry[T]) -> bool:
        """用于堆排序的比较."""
        # 优先级高的在后，访问时间早的在前（优先淘汰）
        if self.priority != other.priority:
            return self.priority < other.priority
        return self.last_accessed < other.last_accessed


@dataclass
class CacheStats:
    """缓存统计数据类.

    Attributes:
        hits: 命中次数
        misses: 未命中次数
        evictions: 淘汰次数
        expirations: 过期次数
        total_size_bytes: 总大小（字节）
        entry_count: 条目数量
        writes: 写入次数
        deletes: 删除次数
        warmup_count: 预热条目数

    Example:
        ```python
        stats = CacheStats()
        stats.record_hit()
        print(f"命中率：{stats.hit_rate:.2%}")
        ```
    """

    hits: int = 0
    misses: int = 0
    evictions: int = 0
    expirations: int = 0
    total_size_bytes: int = 0
    entry_count: int = 0
    writes: int = 0
    deletes: int = 0
    warmup_count: int = 0

    # 性能追踪
    total_get_time_ms: float = 0.0
    total_set_time_ms: float = 0.0
    operation_count: int = 0

    def record_hit(self, time_ms: float = 0.0) -> None:
        """记录一次命中.

        Args:
            time_ms: 操作耗时（毫秒）
        """
        self.hits += 1
        self.total_get_time_ms += time_ms
        self.operation_count += 1

    def record_miss(self, time_ms: float = 0.0) -> None:
        """记录一次未命中.

        Args:
            time_ms: 操作耗时（毫秒）
        """
        self.misses += 1
        self.total_get_time_ms += time_ms
        self.operation_count += 1

    def record_eviction(self) -> None:
        """记录一次淘汰."""
        self.evictions += 1

    def record_expiration(self) -> None:
        """记录一次过期."""
        self.expirations += 1

    def record_write(self, time_ms: float = 0.0) -> None:
        """记录一次写入.

        Args:
            time_ms: 操作耗时（毫秒）
        """
        self.writes += 1
        self.total_set_time_ms += time_ms
        self.operation_count += 1

    def record_delete(self) -> None:
        """记录一次删除."""
        self.deletes += 1

    def record_warmup(self) -> None:
        """记录一次预热."""
        self.warmup_count += 1

    @property
    def hit_rate(self) -> float:
        """计算命中率.

        Returns:
            命中率 (0.0 - 1.0)
        """
        total = self.hits + self.misses
        if total == 0:
            return 0.0
        return self.hits / total

    @property
    def miss_rate(self) -> float:
        """计算未命中率.

        Returns:
            未命中率 (0.0 - 1.0)
        """
        return 1.0 - self.hit_rate

    @property
    def avg_get_time_ms(self) -> float:
        """获取平均读取时间."""
        ops = self.hits + self.misses
        if ops == 0:
            return 0.0
        return self.total_get_time_ms / ops

    @property
    def avg_set_time_ms(self) -> float:
        """获取平均写入时间."""
        if self.writes == 0:
            return 0.0
        return self.total_set_time_ms / self.writes

    def to_dict(self) -> dict[str, Any]:
        """转换为字典格式."""
        return {
            "hits": self.hits,
            "misses": self.misses,
            "evictions": self.evictions,
            "expirations": self.expirations,
            "total_size_bytes": self.total_size_bytes,
            "entry_count": self.entry_count,
            "writes": self.writes,
            "deletes": self.deletes,
            "warmup_count": self.warmup_count,
            "hit_rate": self.hit_rate,
            "miss_rate": self.miss_rate,
            "avg_get_time_ms": self.avg_get_time_ms,
            "avg_set_time_ms": self.avg_set_time_ms,
        }

    def reset(self) -> None:
        """重置统计数据."""
        self.hits = 0
        self.misses = 0
        self.evictions = 0
        self.expirations = 0
        self.total_size_bytes = 0
        self.entry_count = 0
        self.writes = 0
        self.deletes = 0
        self.warmup_count = 0
        self.total_get_time_ms = 0.0
        self.total_set_time_ms = 0.0
        self.operation_count = 0


@dataclass
class CacheMonitor:
    """缓存监控器.

    提供实时监控功能，追踪缓存状态和性能指标.

    Attributes:
        sample_interval: 采样间隔（秒）
        max_samples: 最大样本数
    """

    sample_interval: float = 1.0
    max_samples: int = 100

    def __post_init__(self) -> None:
        self._samples: list[dict[str, Any]] = []
        self._alerts: list[dict[str, Any]] = []
        self._running = False
        self._monitor_task: Optional[asyncio.Task] = None

    def record_sample(self, stats: CacheStats, memory_usage: int) -> None:
        """记录样本.

        Args:
            stats: 缓存统计
            memory_usage: 内存使用量
        """
        sample = {
            "timestamp": time.time(),
            "hit_rate": stats.hit_rate,
            "entry_count": stats.entry_count,
            "total_size_bytes": stats.total_size_bytes,
            "memory_usage": memory_usage,
            "evictions": stats.evictions,
            "expirations": stats.expirations,
        }
        self._samples.append(sample)

        # 限制样本数量
        if len(self._samples) > self.max_samples:
            self._samples = self._samples[-self.max_samples:]

        # 检查告警
        self._check_alerts(sample)

    def _check_alerts(self, sample: dict[str, Any]) -> None:
        """检查是否需要告警.

        Args:
            sample: 当前样本
        """
        alerts = []

        # 低命中率告警
        if sample["hit_rate"] < 0.3 and sample["entry_count"] > 10:
            alerts.append({
                "type": "low_hit_rate",
                "message": f"命中率过低：{sample['hit_rate']:.2%}",
                "severity": "warning",
                "timestamp": sample["timestamp"],
            })

        # 高淘汰率告警
        if sample["evictions"] > sample["entry_count"] * 0.5:
            alerts.append({
                "type": "high_eviction",
                "message": f"淘汰率过高：{sample['evictions']} 次",
                "severity": "warning",
                "timestamp": sample["timestamp"],
            })

        self._alerts.extend(alerts)

        # 限制告警数量
        if len(self._alerts) > 100:
            self._alerts = self._alerts[-100:]

    def get_recent_samples(self, count: int = 10) -> list[dict[str, Any]]:
        """获取最近的样本.

        Args:
            count: 样本数量

        Returns:
            样本列表
        """
        return self._samples[-count:]

    def get_alerts(self, clear: bool = False) -> list[dict[str, Any]]:
        """获取告警列表.

        Args:
            clear: 是否清空告警

        Returns:
            告警列表
        """
        alerts = self._alerts.copy()
        if clear:
            self._alerts.clear()
        return alerts

    def get_trend(self) -> dict[str, str]:
        """获取趋势分析.

        Returns:
            趋势分析结果
        """
        if len(self._samples) < 2:
            return {"hit_rate": "stable", "size": "stable"}

        recent = self._samples[-10:]
        older = self._samples[:-10] if len(self._samples) > 10 else self._samples[:5]

        recent_hit_rate = sum(s["hit_rate"] for s in recent) / len(recent)
        older_hit_rate = sum(s["hit_rate"] for s in older) / len(older)

        recent_size = sum(s["total_size_bytes"] for s in recent) / len(recent)
        older_size = sum(s["total_size_bytes"] for s in older) / len(older)

        def trend(current: float, previous: float) -> str:
            diff = (current - previous) / previous if previous > 0 else 0
            if diff > 0.1:
                return "increasing"
            elif diff < -0.1:
                return "decreasing"
            return "stable"

        return {
            "hit_rate": trend(recent_hit_rate, older_hit_rate),
            "size": trend(recent_size, older_size),
        }


class EvictionPolicy:
    """淘汰策略基类."""

    def select_victim(self, cache: OrderedDict[str, CacheEntry]) -> Optional[str]:
        """选择要淘汰的条目.

        Args:
            cache: 缓存字典

        Returns:
            要淘汰的键
        """
        raise NotImplementedError


class LRUPolicy(EvictionPolicy):
    """LRU (Least Recently Used) 淘汰策略."""

    def select_victim(self, cache: OrderedDict[str, CacheEntry]) -> Optional[str]:
        """选择最近最少使用的条目.

        Args:
            cache: 缓存字典

        Returns:
            要淘汰的键
        """
        if not cache:
            return None
        # OrderedDict 的第一个元素是最久未使用的
        return next(iter(cache))


class LFUPolicy(EvictionPolicy):
    """LFU (Least Frequently Used) 淘汰策略."""

    def select_victim(self, cache: OrderedDict[str, CacheEntry]) -> Optional[str]:
        """选择访问频率最低的条目.

        Args:
            cache: 缓存字典

        Returns:
            要淘汰的键
        """
        if not cache:
            return None
        return min(cache.keys(), key=lambda k: cache[k].access_count)


class TTLPolicy(EvictionPolicy):
    """TTL (Time To Live) 淘汰策略."""

    def select_victim(self, cache: OrderedDict[str, CacheEntry]) -> Optional[str]:
        """选择最早过期的条目.

        Args:
            cache: 缓存字典

        Returns:
            要淘汰的键
        """
        if not cache:
            return None
        return min(cache.keys(), key=lambda k: cache[k].expires_at)


class PriorityPolicy(EvictionPolicy):
    """优先级淘汰策略."""

    def select_victim(self, cache: OrderedDict[str, CacheEntry]) -> Optional[str]:
        """选择优先级最低的条目.

        Args:
            cache: 缓存字典

        Returns:
            要淘汰的键
        """
        if not cache:
            return None
        return min(cache.keys(), key=lambda k: cache[k].priority)


class CacheManager:
    """智能缓存管理器.

    提供多层缓存管理，支持内存缓存和磁盘缓存，
    使用 LRU 策略进行淘汰，支持自动过期清理.

    Attributes:
        ttl: 默认生存时间（秒）
        max_size: 最大缓存条目数
        max_memory_mb: 最大内存占用（MB）
        use_disk_cache: 是否启用磁盘缓存
        disk_cache_path: 磁盘缓存路径

    Example:
        ```python
        cache = CacheManager(
            ttl=3600,
            max_size=10000,
            max_memory_mb=512,
            use_disk_cache=True,
            disk_cache_path="/tmp/cache"
        )
        await cache.initialize()
        await cache.set("key", {"data": "value"})
        ```

    Note:
        - 内存缓存使用 OrderedDict 实现 LRU 策略
        - 磁盘缓存使用 ZSTD 压缩存储减少空间占用
        - 定期后台清理过期条目
        - 支持实时监控和告警
    """

    DEFAULT_TTL = 3600  # 1 小时
    DEFAULT_MAX_SIZE = 10000
    DEFAULT_MAX_MEMORY_MB = 512
    CLEANUP_INTERVAL = 60  # 1 分钟
    MONITOR_INTERVAL = 5  # 5 秒

    def __init__(
        self,
        ttl: int = DEFAULT_TTL,
        max_size: int = DEFAULT_MAX_SIZE,
        max_memory_mb: int = DEFAULT_MAX_MEMORY_MB,
        use_disk_cache: bool = False,
        disk_cache_path: str | Path | None = None,
        eviction_policy: str = "lru",
        compression_level: int = 3,
        enable_monitoring: bool = True,
    ) -> None:
        """初始化缓存管理器.

        Args:
            ttl: 默认生存时间（秒）
            max_size: 最大缓存条目数
            max_memory_mb: 最大内存占用（MB）
            use_disk_cache: 是否启用磁盘缓存
            disk_cache_path: 磁盘缓存路径
            eviction_policy: 淘汰策略 ("lru", "lfu", "ttl", "priority")
            compression_level: 磁盘缓存压缩级别
            enable_monitoring: 启用监控

        Raises:
            ValueError: 参数值无效
        """
        if ttl <= 0:
            raise ValueError("TTL 必须大于 0")
        if max_size <= 0:
            raise ValueError("max_size 必须大于 0")
        if max_memory_mb <= 0:
            raise ValueError("max_memory_mb 必须大于 0")

        self.ttl = ttl
        self.max_size = max_size
        self.max_memory_mb = max_memory_mb
        self.use_disk_cache = use_disk_cache
        self.disk_cache_path = Path(disk_cache_path) if disk_cache_path else None
        self.enable_monitoring = enable_monitoring

        # 淘汰策略
        self._eviction_policy = self._create_eviction_policy(eviction_policy)

        # 磁盘缓存压缩
        self._compressor = zstd.ZstdCompressor(level=compression_level)
        self._decompressor = zstd.ZstdDecompressor()

        # 内存缓存
        self._cache: OrderedDict[str, CacheEntry[Any]] = OrderedDict()

        # 统计信息
        self._stats = CacheStats()

        # 监控器
        self._monitor = CacheMonitor() if enable_monitoring else None

        # 锁
        self._lock = asyncio.Lock()

        # 后台任务
        self._cleanup_task: Optional[asyncio.Task] = None
        self._monitor_task: Optional[asyncio.Task] = None
        self._running = False

    def _create_eviction_policy(self, policy: str) -> EvictionPolicy:
        """创建淘汰策略.

        Args:
            policy: 策略名称

        Returns:
            淘汰策略实例
        """
        policies = {
            "lru": LRUPolicy,
            "lfu": LFUPolicy,
            "ttl": TTLPolicy,
            "priority": PriorityPolicy,
        }
        policy_class = policies.get(policy.lower(), LRUPolicy)
        return policy_class()

    async def initialize(self) -> None:
        """初始化缓存管理器.

        创建磁盘缓存目录（如果启用），启动后台清理任务.
        """
        if self.use_disk_cache and self.disk_cache_path:
            self.disk_cache_path.mkdir(parents=True, exist_ok=True)
            logger.info(f"磁盘缓存目录：{self.disk_cache_path}")

        self._running = True

        # 启动清理任务
        self._cleanup_task = asyncio.create_task(self._cleanup_loop())

        # 启动监控任务
        if self.enable_monitoring:
            self._monitor_task = asyncio.create_task(self._monitor_loop())

        logger.info("缓存管理器初始化完成")

    async def close(self) -> None:
        """关闭缓存管理器.

        停止后台清理任务，释放资源.
        """
        self._running = False

        # 取消清理任务
        if self._cleanup_task:
            self._cleanup_task.cancel()
            try:
                await self._cleanup_task
            except asyncio.CancelledError:
                pass

        # 取消监控任务
        if self._monitor_task:
            self._monitor_task.cancel()
            try:
                await self._monitor_task
            except asyncio.CancelledError:
                pass

        logger.info("缓存管理器已关闭")

    async def __aenter__(self) -> CacheManager:
        """异步上下文管理器入口."""
        await self.initialize()
        return self

    async def __aexit__(self, exc_type: Any, exc_val: Any, exc_tb: Any) -> None:
        """异步上下文管理器出口."""
        await self.close()

    def _compute_key(self, key: str) -> str:
        """计算缓存键的哈希值.

        Args:
            key: 原始键

        Returns:
            哈希后的键
        """
        return hashlib.sha256(key.encode("utf-8")).hexdigest()[:16]

    def _estimate_size(self, value: Any) -> int:
        """估算值的内存大小.

        Args:
            value: 要估算的值

        Returns:
            估算的字节数
        """
        try:
            serialized = json.dumps(value)
            return len(serialized.encode("utf-8"))
        except (TypeError, ValueError):
            return 1024  # 默认估算 1KB

    def _get_memory_usage(self) -> int:
        """获取当前内存使用量.

        Returns:
            内存使用量（字节）
        """
        try:
            import resource
            return resource.getrusage(resource.RUSAGE_SELF).ru_maxrss * 1024
        except ImportError:
            # Windows/Android  fallback
            return self._stats.total_size_bytes

    def _evict(self) -> Optional[str]:
        """执行淘汰.

        Returns:
            被淘汰的键
        """
        victim_key = self._eviction_policy.select_victim(self._cache)
        if victim_key:
            entry = self._cache.pop(victim_key)
            self._stats.total_size_bytes -= entry.size_bytes
            self._stats.record_eviction()
            logger.debug(f"淘汰缓存条目：{victim_key}")
        return victim_key

    async def set(
        self,
        key: str,
        value: Any,
        ttl: int | None = None,
        priority: int = 0,
    ) -> None:
        """设置缓存值.

        Args:
            key: 缓存键
            value: 缓存值
            ttl: 生存时间（秒），使用默认值如果为 None
            priority: 优先级（越高越不容易被淘汰）

        Raises:
            RuntimeError: 缓存未初始化
        """
        start_time = time.perf_counter()

        async with self._lock:
            cache_key = self._compute_key(key)
            now = time.time()
            effective_ttl = ttl if ttl is not None else self.ttl

            # 检查是否需要淘汰
            while len(self._cache) >= self.max_size:
                self._evict()

            # 检查内存限制
            estimated_size = self._estimate_size(value)
            max_memory_bytes = self.max_memory_mb * 1024 * 1024

            while (
                self._stats.total_size_bytes + estimated_size > max_memory_bytes
                and len(self._cache) > 0
            ):
                self._evict()

            # 创建缓存条目
            entry: CacheEntry[Any] = CacheEntry(
                value=value,
                created_at=now,
                expires_at=now + effective_ttl,
                size_bytes=estimated_size,
                key=key,
                priority=priority,
            )
            entry.touch()

            # 如果键已存在，先移除旧条目
            if cache_key in self._cache:
                old_entry = self._cache[cache_key]
                self._stats.total_size_bytes -= old_entry.size_bytes

            self._cache[cache_key] = entry
            self._stats.total_size_bytes += entry.size_bytes
            self._stats.entry_count = len(self._cache)
            self._stats.record_write(
                (time.perf_counter() - start_time) * 1000
            )

            # 如果启用磁盘缓存，持久化
            if self.use_disk_cache and self.disk_cache_path:
                await self._persist_to_disk(cache_key, entry)

        logger.debug(f"设置缓存：{key}, 大小={estimated_size}B")

    async def get(self, key: str, default: Any = None) -> Any | None:
        """获取缓存值.

        Args:
            key: 缓存键
            default: 默认值（如果未找到）

        Returns:
            缓存值，如果不存在或已过期则返回 default
        """
        start_time = time.perf_counter()

        async with self._lock:
            cache_key = self._compute_key(key)

            # 检查内存缓存
            if cache_key in self._cache:
                entry = self._cache[cache_key]

                if entry.is_expired():
                    del self._cache[cache_key]
                    self._stats.total_size_bytes -= entry.size_bytes
                    self._stats.record_expiration()
                    self._stats.entry_count = len(self._cache)
                    elapsed = (time.perf_counter() - start_time) * 1000
                    self._stats.record_miss(elapsed)
                    logger.debug(f"缓存过期：{key}")
                    return default

                # 移动到末尾（LRU）
                self._cache.move_to_end(cache_key)
                entry.touch()
                elapsed = (time.perf_counter() - start_time) * 1000
                self._stats.record_hit(elapsed)
                logger.debug(f"缓存命中：{key}")
                return entry.value

            # 检查磁盘缓存
            if self.use_disk_cache and self.disk_cache_path:
                entry = await self._load_from_disk(cache_key)
                if entry is not None:
                    if entry.is_expired():
                        await self._remove_from_disk(cache_key)
                        self._stats.record_expiration()
                        elapsed = (time.perf_counter() - start_time) * 1000
                        self._stats.record_miss(elapsed)
                        logger.debug(f"磁盘缓存过期：{key}")
                        return default

                    # 加载到内存缓存
                    self._cache[cache_key] = entry
                    self._stats.total_size_bytes += entry.size_bytes
                    self._stats.entry_count = len(self._cache)
                    entry.touch()
                    elapsed = (time.perf_counter() - start_time) * 1000
                    self._stats.record_hit(elapsed)
                    logger.debug(f"磁盘缓存命中：{key}")
                    return entry.value

            elapsed = (time.perf_counter() - start_time) * 1000
            self._stats.record_miss(elapsed)
            logger.debug(f"缓存未命中：{key}")
            return default

    async def get_or_set(
        self,
        key: str,
        factory: Callable[[], Any],
        ttl: int | None = None,
    ) -> Any:
        """获取或设置缓存值.

        Args:
            key: 缓存键
            factory: 工厂函数（用于生成值）
            ttl: 生存时间（秒）

        Returns:
            缓存值
        """
        value = await self.get(key)
        if value is not None:
            return value

        # 生成新值
        if asyncio.iscoroutinefunction(factory):
            value = await factory()
        else:
            value = factory()

        await self.set(key, value, ttl)
        return value

    async def delete(self, key: str) -> bool:
        """删除缓存条目.

        Args:
            key: 缓存键

        Returns:
            如果删除成功返回 True，否则返回 False
        """
        async with self._lock:
            cache_key = self._compute_key(key)

            deleted = False
            if cache_key in self._cache:
                entry = self._cache.pop(cache_key)
                self._stats.total_size_bytes -= entry.size_bytes
                self._stats.entry_count = len(self._cache)
                deleted = True

            if self.use_disk_cache and self.disk_cache_path:
                await self._remove_from_disk(cache_key)

            if deleted:
                self._stats.record_delete()

            return deleted

    async def clear(self) -> None:
        """清空所有缓存."""
        async with self._lock:
            self._cache.clear()
            self._stats.total_size_bytes = 0
            self._stats.entry_count = 0

            if self.use_disk_cache and self.disk_cache_path:
                for file in self.disk_cache_path.glob("*.cache"):
                    file.unlink()

            logger.info("缓存已清空")

    async def _cleanup_loop(self) -> None:
        """后台清理循环."""
        while self._running:
            try:
                await asyncio.sleep(self.CLEANUP_INTERVAL)
                if self._running:
                    await self._cleanup_expired()
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"清理循环错误：{e}")

    async def _cleanup_expired(self) -> int:
        """清理过期的缓存条目.

        Returns:
            清理的条目数
        """
        async with self._lock:
            now = time.time()
            expired_keys = [
                key for key, entry in self._cache.items() if entry.is_expired()
            ]

            for key in expired_keys:
                entry = self._cache.pop(key)
                self._stats.total_size_bytes -= entry.size_bytes
                self._stats.record_expiration()

            self._stats.entry_count = len(self._cache)

            # 清理磁盘缓存
            if self.use_disk_cache and self.disk_cache_path:
                for file in self.disk_cache_path.glob("*.cache"):
                    try:
                        data = await self._read_file(file)
                        decompressed = self._decompressor.decompress(data)
                        entry_data = json.loads(decompressed.decode("utf-8"))
                        if now > entry_data.get("expires_at", 0):
                            file.unlink()
                            logger.debug(f"清理磁盘缓存：{file}")
                    except Exception:
                        pass

            if expired_keys:
                logger.info(f"清理过期缓存：{len(expired_keys)} 条")

            return len(expired_keys)

    async def _persist_to_disk(self, key: str, entry: CacheEntry[Any]) -> None:
        """持久化条目到磁盘.

        Args:
            key: 缓存键
            entry: 缓存条目
        """
        if not self.disk_cache_path:
            return

        try:
            data = json.dumps(entry.to_dict()).encode("utf-8")
            compressed = self._compressor.compress(data)
            await self._write_file(self.disk_cache_path / f"{key}.cache", compressed)
        except Exception as e:
            logger.error(f"持久化到磁盘失败：{e}")

    async def _load_from_disk(self, key: str) -> CacheEntry[Any] | None:
        """从磁盘加载条目.

        Args:
            key: 缓存键

        Returns:
            缓存条目，如果不存在返回 None
        """
        if not self.disk_cache_path:
            return None

        file_path = self.disk_cache_path / f"{key}.cache"
        if not file_path.exists():
            return None

        try:
            compressed = await self._read_file(file_path)
            decompressed = self._decompressor.decompress(compressed)
            entry_data = json.loads(decompressed.decode("utf-8"))
            return CacheEntry.from_dict(entry_data)
        except Exception as e:
            logger.debug(f"从磁盘加载失败：{e}")
            return None

    async def _remove_from_disk(self, key: str) -> None:
        """从磁盘移除条目.

        Args:
            key: 缓存键
        """
        if not self.disk_cache_path:
            return

        file_path = self.disk_cache_path / f"{key}.cache"
        if file_path.exists():
            file_path.unlink()

    async def _write_file(self, path: Path, data: bytes) -> None:
        """异步写入文件.

        Args:
            path: 文件路径
            data: 数据
        """
        await asyncio.get_event_loop().run_in_executor(
            None, lambda: path.write_bytes(data)
        )

    async def _read_file(self, path: Path) -> bytes:
        """异步读取文件.

        Args:
            path: 文件路径

        Returns:
            文件内容
        """
        return await asyncio.get_event_loop().run_in_executor(
            None, lambda: path.read_bytes()
        )

    async def _monitor_loop(self) -> None:
        """后台监控循环."""
        while self._running:
            try:
                await asyncio.sleep(self.MONITOR_INTERVAL)
                if self._running and self._monitor:
                    memory_usage = self._get_memory_usage()
                    self._monitor.record_sample(self._stats, memory_usage)
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"监控循环错误：{e}")

    def get_stats(self) -> CacheStats:
        """获取缓存统计信息.

        Returns:
            缓存统计数据
        """
        return self._stats

    def get_monitor(self) -> CacheMonitor | None:
        """获取监控器.

        Returns:
            监控器实例
        """
        return self._monitor

    async def warm_up(
        self,
        keys: list[str],
        loader: Callable[[str], Any],
        concurrency: int = 5,
    ) -> dict[str, Any]:
        """预热缓存.

        Args:
            keys: 要预热的键列表
            loader: 加载函数，接收键并返回值
            concurrency: 并发加载数量

        Returns:
            预热结果统计

        Example:
            ```python
            async def loader(key):
                return await fetch_data(key)

            result = await cache.warm_up(["key1", "key2"], loader)
            ```
        """
        results = {"success": 0, "failed": 0, "errors": {}}
        semaphore = asyncio.Semaphore(concurrency)

        async def load_key(key: str) -> None:
            async with semaphore:
                try:
                    if asyncio.iscoroutinefunction(loader):
                        value = await loader(key)
                    else:
                        value = loader(key)
                    await self.set(key, value)
                    results["success"] += 1
                    self._stats.record_warmup()
                    logger.debug(f"预热成功：{key}")
                except Exception as e:
                    results["failed"] += 1
                    results["errors"][key] = str(e)
                    logger.warning(f"预热失败：{key}, 错误：{e}")

        tasks = [load_key(key) for key in keys]
        await asyncio.gather(*tasks, return_exceptions=True)

        logger.info(f"缓存预热完成：成功={results['success']}, 失败={results['failed']}")
        return results

    async def get_entry(self, key: str) -> CacheEntry[Any] | None:
        """获取缓存条目（包含元数据）.

        Args:
            key: 缓存键

        Returns:
            缓存条目，如果不存在返回 None
        """
        async with self._lock:
            cache_key = self._compute_key(key)
            return self._cache.get(cache_key)

    async def get_all_entries(self) -> list[CacheEntry[Any]]:
        """获取所有缓存条目.

        Returns:
            缓存条目列表
        """
        async with self._lock:
            return list(self._cache.values())

    async def get_report(self) -> dict[str, Any]:
        """获取缓存报告.

        Returns:
            缓存报告字典
        """
        stats = self._stats.to_dict()

        report = {
            "statistics": stats,
            "configuration": {
                "ttl": self.ttl,
                "max_size": self.max_size,
                "max_memory_mb": self.max_memory_mb,
                "use_disk_cache": self.use_disk_cache,
                "eviction_policy": self._eviction_policy.__class__.__name__,
            },
            "entries": {
                "total": len(self._cache),
                "expired": sum(1 for e in self._cache.values() if e.is_expired()),
            },
        }

        if self._monitor:
            report["monitoring"] = {
                "trend": self._monitor.get_trend(),
                "alerts": self._monitor.get_alerts(clear=True),
                "recent_samples": self._monitor.get_recent_samples(5),
            }

        return report

    async def export_entries(self, path: str | Path) -> int:
        """导出所有缓存条目到文件.

        Args:
            path: 导出文件路径

        Returns:
            导出的条目数
        """
        async with self._lock:
            entries = [entry.to_dict() for entry in self._cache.values()]

            data = json.dumps(entries, indent=2).encode("utf-8")
            compressed = self._compressor.compress(data)

            export_path = Path(path)
            export_path.parent.mkdir(parents=True, exist_ok=True)
            export_path.write_bytes(compressed)

            logger.info(f"导出缓存：{len(entries)} 条到 {path}")
            return len(entries)

    async def import_entries(self, path: str | Path) -> int:
        """从文件导入缓存条目.

        Args:
            path: 导入文件路径

        Returns:
            导入的条目数
        """
        import_path = Path(path)
        if not import_path.exists():
            raise FileNotFoundError(f"导入文件不存在：{path}")

        compressed = import_path.read_bytes()
        decompressed = self._decompressor.decompress(compressed)
        entries_data = json.loads(decompressed.decode("utf-8"))

        async with self._lock:
            count = 0
            for data in entries_data:
                entry = CacheEntry.from_dict(data)
                cache_key = self._compute_key(entry.key)
                self._cache[cache_key] = entry
                self._stats.total_size_bytes += entry.size_bytes
                count += 1

            self._stats.entry_count = len(self._cache)

            logger.info(f"导入缓存：{count} 条从 {path}")
            return count


class CacheManagerFactory:
    """缓存管理器工厂.

    提供便捷的缓存管理器创建方法.
    """

    @staticmethod
    def create_memory_cache(
        ttl: int = 3600,
        max_size: int = 10000,
        max_memory_mb: int = 256,
        eviction_policy: str = "lru",
    ) -> CacheManager:
        """创建纯内存缓存.

        Args:
            ttl: 默认生存时间
            max_size: 最大条目数
            max_memory_mb: 最大内存占用
            eviction_policy: 淘汰策略

        Returns:
            CacheManager 实例
        """
        return CacheManager(
            ttl=ttl,
            max_size=max_size,
            max_memory_mb=max_memory_mb,
            use_disk_cache=False,
            eviction_policy=eviction_policy,
        )

    @staticmethod
    def create_disk_cache(
        disk_path: str | Path,
        ttl: int = 3600,
        max_size: int = 100000,
        compression_level: int = 3,
    ) -> CacheManager:
        """创建磁盘缓存.

        Args:
            disk_path: 磁盘缓存路径
            ttl: 默认生存时间
            max_size: 最大条目数
            compression_level: 压缩级别

        Returns:
            CacheManager 实例
        """
        return CacheManager(
            ttl=ttl,
            max_size=max_size,
            use_disk_cache=True,
            disk_cache_path=disk_path,
            compression_level=compression_level,
            enable_monitoring=False,
        )

    @staticmethod
    def create_hybrid_cache(
        disk_path: str | Path,
        memory_max_size: int = 1000,
        disk_max_size: int = 100000,
        ttl: int = 3600,
    ) -> CacheManager:
        """创建混合缓存（内存 + 磁盘）.

        Args:
            disk_path: 磁盘缓存路径
            memory_max_size: 内存最大条目数
            disk_max_size: 磁盘最大条目数
            ttl: 默认生存时间

        Returns:
            CacheManager 实例
        """
        return CacheManager(
            ttl=ttl,
            max_size=memory_max_size,
            use_disk_cache=True,
            disk_cache_path=disk_path,
            eviction_policy="lru",
            enable_monitoring=True,
        )
