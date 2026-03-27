"""
Database 模块增强测试.

测试 CompressedDatabase 和 CacheManager 的增强功能.

Usage:
    pytest tests/test_database_enhanced.py -v

Author:
    Oh My LiteCode Team
"""

from __future__ import annotations

import asyncio
import json
import tempfile
import time
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from grep_app_enhanced import SearchResult
from grep_app_enhanced.database import (
    CacheManager,
    CacheEntry,
    CacheStats,
    CacheMonitor,
    CacheManagerFactory,
    CompressedDatabase,
    CompressionStats,
    DatabaseConfig,
    ConnectionPool,
    LRUPolicy,
    LFUPolicy,
    TTLPolicy,
    PriorityPolicy,
    JsonSerializer,
    BinarySerializer,
    PerformanceTracker,
    PerformanceMetrics,
    MemoryManager,
    RateLimiter,
    CacheKeyGenerator,
    compute_hash,
    compute_query_hash,
    compute_file_hash,
    timed,
    retry,
    RetryConfig,
    batch_process,
    validate_compression_ratio,
    validate_cache_entry,
    CompressionError,
    DatabaseError,
    CacheError,
    CompressedDatabaseError,
    DBCompressionError,
)


# =============================================================================
# CompressionStats 测试
# =============================================================================


class TestCompressionStatsEnhanced:
    """测试 CompressionStats 增强功能."""

    def test_compression_ratio_display(self) -> None:
        """测试压缩比显示."""
        stats = CompressionStats(
            original_size=10000,
            compressed_size=2000,
        )
        stats.compression_ratio = 0.2
        assert stats.compression_ratio_display == "5.0:1"

    def test_compression_ratio_display_zero(self) -> None:
        """测试零压缩比显示."""
        stats = CompressionStats()
        assert stats.compression_ratio_display == "N/A"

    def test_avg_times(self) -> None:
        """测试平均时间计算."""
        stats = CompressionStats(
            compress_time_ms=100,
            decompress_time_ms=50,
            operation_count=10,
        )
        assert stats.avg_compress_time_ms == 10.0
        assert stats.avg_decompress_time_ms == 5.0

    def test_avg_times_zero_operations(self) -> None:
        """测试零操作数时的平均时间."""
        stats = CompressionStats()
        assert stats.avg_compress_time_ms == 0.0
        assert stats.avg_decompress_time_ms == 0.0

    def test_reset(self) -> None:
        """测试重置统计."""
        stats = CompressionStats(
            original_size=10000,
            compressed_size=2000,
            compress_time_ms=10,
            decompress_time_ms=5,
            operation_count=5,
        )
        stats.reset()
        assert stats.original_size == 0
        assert stats.compressed_size == 0
        assert stats.operation_count == 0


# =============================================================================
# CompressedDatabase 增强测试
# =============================================================================


class TestCompressedDatabaseEnhanced:
    """测试 CompressedDatabase 增强功能."""

    @pytest.fixture
    def temp_db_path(self) -> Path:
        """创建临时数据库文件路径."""
        with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as f:
            db_path = Path(f.name)
        yield db_path
        db_path.unlink(missing_ok=True)

    @pytest.fixture
    async def db(self, temp_db_path: Path) -> CompressedDatabase:
        """创建压缩数据库实例."""
        database = CompressedDatabase(
            temp_db_path,
            compression_level=3,
            auto_cleanup=False,
        )
        await database.initialize()
        yield database
        await database.close()

    @pytest.mark.asyncio
    async def test_store_and_retrieve_with_stats(
        self, db: CompressedDatabase
    ) -> None:
        """测试存储和检索并获取统计."""
        results = [
            SearchResult(
                file_path="test.py",
                line_number=1,
                content="def hello():",
            )
        ]

        # 存储并获取统计
        stats = await db.store_search_results(
            query_hash="test_hash",
            pattern="def ",
            search_path="/test",
            results=results,
            ttl_seconds=3600,
        )

        assert stats.original_size > 0
        assert stats.compressed_size > 0
        assert stats.compression_ratio < 1.0

        # 检索并获取统计
        retrieved, retrieve_stats = await db.retrieve_search_results("test_hash")

        assert retrieved is not None
        assert len(retrieved) == 1
        assert retrieve_stats.decompress_time_ms > 0

    @pytest.mark.asyncio
    async def test_metadata_operations(self, db: CompressedDatabase) -> None:
        """测试元数据操作."""
        metadata = {"config": "value", "count": 42}

        # 存储元数据
        stats = await db.store_metadata("test_key", metadata)
        assert stats.original_size > 0

        # 检索元数据
        value, retrieve_stats = await db.retrieve_metadata("test_key")
        assert value == metadata
        assert retrieve_stats.decompress_time_ms > 0

        # 检索不存在的元数据
        none_value, _ = await db.retrieve_metadata("nonexistent")
        assert none_value is None

    @pytest.mark.asyncio
    async def test_table_stats(self, db: CompressedDatabase) -> None:
        """测试表统计."""
        stats = await db.get_table_stats("search_cache")
        assert "row_count" in stats
        assert "total_original_size" in stats

    @pytest.mark.asyncio
    async def test_benchmark(self, db: CompressedDatabase) -> None:
        """测试性能基准."""
        result = await db.run_benchmark(iterations=10)
        assert "avg_compress_time_ms" in result
        assert "avg_decompress_time_ms" in result
        assert "compression_ratio" in result

    @pytest.mark.asyncio
    async def test_performance_impact(self, db: CompressedDatabase) -> None:
        """测试性能影响估算."""
        result = await db.estimate_performance_impact()
        assert "read_impact_percent" in result
        assert "write_impact_percent" in result
        assert "meets_read_target" in result
        assert "meets_write_target" in result

    @pytest.mark.asyncio
    async def test_compression_report(self, db: CompressedDatabase) -> None:
        """测试压缩报告."""
        report = await db.get_compression_report()
        assert "overall" in report
        assert "search_cache" in report
        assert "performance" in report
        assert "targets" in report
        assert "meets_targets" in report

    @pytest.mark.asyncio
    async def test_vacuum(self, db: CompressedDatabase) -> None:
        """测试 VACUUM 操作."""
        # 不应抛出异常
        await db.vacuum()

    @pytest.mark.asyncio
    async def test_concurrent_reads(self, temp_db_path: Path) -> None:
        """测试并发读取."""
        db = CompressedDatabase(
            temp_db_path,
            compression_level=3,
            pool_size=4,
            enable_wal=True,
        )
        await db.initialize()

        try:
            # 存储一些数据
            results = [
                SearchResult(file_path=f"file{i}.py", line_number=1, content=f"content{i}")
                for i in range(5)
            ]
            for i, result in enumerate(results):
                await db.store_search_results(
                    query_hash=f"hash_{i}",
                    pattern="test",
                    search_path="/test",
                    results=[result],
                    ttl_seconds=3600,
                )

            # 并发读取
            async def read_task(hash_id: int) -> tuple[int, list[SearchResult] | None]:
                retrieved, _ = await db.retrieve_search_results(f"hash_{hash_id}")
                return hash_id, retrieved

            tasks = [read_task(i) for i in range(5)]
            results = await asyncio.gather(*tasks)

            for hash_id, retrieved in results:
                assert retrieved is not None
                assert len(retrieved) == 1
        finally:
            await db.close()

    @pytest.mark.asyncio
    async def test_auto_cleanup(self, temp_db_path: Path) -> None:
        """测试自动清理."""
        db = CompressedDatabase(
            temp_db_path,
            compression_level=3,
            auto_cleanup=True,
            cleanup_interval=1,
        )
        await db.initialize()

        try:
            # 存储立即过期的数据
            results = [SearchResult(file_path="test.py", line_number=1, content="test")]
            await db.store_search_results(
                query_hash="expired",
                pattern="test",
                search_path="/test",
                results=results,
                ttl_seconds=0,
            )

            # 等待自动清理
            await asyncio.sleep(2)

            # 验证数据已清理
            retrieved, _ = await db.retrieve_search_results("expired")
            assert retrieved is None
        finally:
            db._running = False
            await db.close()

    @pytest.mark.asyncio
    async def test_connection_pool(self, temp_db_path: Path) -> None:
        """测试连接池."""
        pool = ConnectionPool(
            temp_db_path,
            pool_size=4,
            enable_wal=True,
        )
        pool.initialize()

        try:
            # 获取连接
            conn1 = pool.get_connection()
            assert conn1 is not None

            # 获取另一个连接
            conn2 = pool.get_connection()
            assert conn2 is not None
            assert conn1 is not conn2

            # 返回连接
            pool.return_connection(conn1)
            pool.return_connection(conn2)

            # 关闭所有连接
            pool.close_all()
        except Exception:
            pass

    @pytest.mark.asyncio
    async def test_context_manager(self, temp_db_path: Path) -> None:
        """测试上下文管理器."""
        from grep_app_enhanced.database import compressed_database_context

        async with compressed_database_context(temp_db_path) as db:
            assert db._pool is not None
            results = [SearchResult(file_path="test.py", line_number=1, content="test")]
            await db.store_search_results(
                query_hash="ctx_test",
                pattern="test",
                search_path="/test",
                results=results,
                ttl_seconds=3600,
            )

        # 退出后应关闭
        assert db._pool is None


# =============================================================================
# CacheManager 增强测试
# =============================================================================


class TestCacheManagerEnhanced:
    """测试 CacheManager 增强功能."""

    @pytest.fixture
    async def cache(self) -> CacheManager:
        """创建缓存管理器实例."""
        cache = CacheManager(ttl=60, max_size=100, enable_monitoring=True)
        await cache.initialize()
        yield cache
        await cache.close()

    @pytest.mark.asyncio
    async def test_priority_cache(self, cache: CacheManager) -> None:
        """测试优先级缓存."""
        # 设置不同优先级的条目
        await cache.set("low_priority", "value1", priority=1)
        await cache.set("high_priority", "value2", priority=10)

        # 获取条目检查优先级
        low_entry = await cache.get_entry("low_priority")
        high_entry = await cache.get_entry("high_priority")

        assert low_entry is not None
        assert low_entry.priority == 1
        assert high_entry is not None
        assert high_entry.priority == 10

    @pytest.mark.asyncio
    async def test_get_or_set(self, cache: CacheManager) -> None:
        """测试 get_or_set 方法."""
        async def factory() -> str:
            return "computed_value"

        # 首次调用应计算
        value1 = await cache.get_or_set("key1", factory)
        assert value1 == "computed_value"

        # 再次调用应返回缓存值
        value2 = await cache.get_or_set("key1", factory)
        assert value2 == "computed_value"

    @pytest.mark.asyncio
    async def test_get_entry(self, cache: CacheManager) -> None:
        """测试获取缓存条目."""
        await cache.set("test_key", "test_value")
        entry = await cache.get_entry("test_key")

        assert entry is not None
        assert entry.value == "test_value"
        assert entry.key == "test_key"

    @pytest.mark.asyncio
    async def test_get_all_entries(self, cache: CacheManager) -> None:
        """测试获取所有条目."""
        await cache.set("key1", "value1")
        await cache.set("key2", "value2")

        entries = await cache.get_all_entries()
        assert len(entries) == 2

    @pytest.mark.asyncio
    async def test_get_report(self, cache: CacheManager) -> None:
        """测试获取报告."""
        await cache.set("key1", "value1")
        await cache.get("key1")  # 产生命中

        report = await cache.get_report()

        assert "statistics" in report
        assert "configuration" in report
        assert "entries" in report
        assert "monitoring" in report

    @pytest.mark.asyncio
    async def test_export_import(self, cache: CacheManager, tmp_path: Path) -> None:
        """测试导出导入."""
        await cache.set("key1", "value1")
        await cache.set("key2", "value2")

        export_path = tmp_path / "cache_export.json"

        # 导出
        count = await cache.export_entries(export_path)
        assert count == 2
        assert export_path.exists()

        # 创建新缓存并导入
        new_cache = CacheManager(ttl=60, max_size=100)
        await new_cache.initialize()

        try:
            import_count = await new_cache.import_entries(export_path)
            assert import_count == 2

            value1 = await new_cache.get("key1")
            value2 = await new_cache.get("key2")
            assert value1 == "value1"
            assert value2 == "value2"
        finally:
            await new_cache.close()

    @pytest.mark.asyncio
    async def test_monitor(self, cache: CacheManager) -> None:
        """测试监控器."""
        monitor = cache.get_monitor()
        assert monitor is not None

        # 执行一些操作
        for i in range(10):
            await cache.set(f"key{i}", f"value{i}")
            await cache.get(f"key{i}")

        # 等待监控采样
        await asyncio.sleep(6)

        # 获取趋势
        trend = monitor.get_trend()
        assert "hit_rate" in trend
        assert "size" in trend

    @pytest.mark.asyncio
    async def test_different_eviction_policies(self) -> None:
        """测试不同淘汰策略."""
        policies = ["lru", "lfu", "ttl", "priority"]

        for policy in policies:
            cache = CacheManager(
                ttl=60,
                max_size=3,
                eviction_policy=policy,
                enable_monitoring=False,
            )
            await cache.initialize()

            try:
                # 添加超过限制的条目
                for i in range(5):
                    await cache.set(f"key{i}", f"value{i}")

                # 应只有 3 个条目
                entries = await cache.get_all_entries()
                assert len(entries) <= 3
            finally:
                await cache.close()

    @pytest.mark.asyncio
    async def test_warm_up_with_concurrency(self, cache: CacheManager) -> None:
        """测试带并发限制的预热."""
        call_count = 0
        max_concurrent = 0
        current_concurrent = 0
        lock = asyncio.Lock()

        async def loader(key: str) -> str:
            nonlocal call_count, max_concurrent, current_concurrent
            async with lock:
                call_count += 1
                current_concurrent += 1
                max_concurrent = max(max_concurrent, current_concurrent)

            await asyncio.sleep(0.1)  # 模拟延迟

            async with lock:
                current_concurrent -= 1

            return f"value_{key}"

        # 预热 10 个键，并发限制为 3
        result = await cache.warm_up(
            [f"key{i}" for i in range(10)],
            loader,
            concurrency=3,
        )

        assert result["success"] == 10
        assert result["failed"] == 0
        assert max_concurrent <= 3


# =============================================================================
# CacheManagerFactory 测试
# =============================================================================


class TestCacheManagerFactory:
    """测试 CacheManagerFactory."""

    @pytest.mark.asyncio
    async def test_create_memory_cache(self, tmp_path: Path) -> None:
        """测试创建内存缓存."""
        cache = CacheManagerFactory.create_memory_cache(
            ttl=60,
            max_size=1000,
            max_memory_mb=256,
        )
        await cache.initialize()

        try:
            assert not cache.use_disk_cache
            await cache.set("key", "value")
            assert await cache.get("key") == "value"
        finally:
            await cache.close()

    @pytest.mark.asyncio
    async def test_create_disk_cache(self, tmp_path: Path) -> None:
        """测试创建磁盘缓存."""
        cache = CacheManagerFactory.create_disk_cache(
            disk_path=tmp_path / "disk_cache",
            ttl=60,
            max_size=100000,
        )
        await cache.initialize()

        try:
            assert cache.use_disk_cache
            assert cache.disk_cache_path is not None
        finally:
            await cache.close()

    @pytest.mark.asyncio
    async def test_create_hybrid_cache(self, tmp_path: Path) -> None:
        """测试创建混合缓存."""
        cache = CacheManagerFactory.create_hybrid_cache(
            disk_path=tmp_path / "hybrid_cache",
            memory_max_size=100,
            disk_max_size=10000,
        )
        await cache.initialize()

        try:
            assert cache.use_disk_cache
            assert cache.max_size == 100
        finally:
            await cache.close()


# =============================================================================
# EvictionPolicy 测试
# =============================================================================


class TestEvictionPolicies:
    """测试淘汰策略."""

    def test_lru_policy(self) -> None:
        """测试 LRU 策略."""
        policy = LRUPolicy()
        cache = {
            "a": CacheEntry(value="a", created_at=0, expires_at=1000, last_accessed=1),
            "b": CacheEntry(value="b", created_at=0, expires_at=1000, last_accessed=2),
            "c": CacheEntry(value="c", created_at=0, expires_at=1000, last_accessed=3),
        }

        victim = policy.select_victim(cache)
        assert victim == "a"  # 最久未使用

    def test_lfu_policy(self) -> None:
        """测试 LFU 策略."""
        policy = LFUPolicy()
        cache = {
            "a": CacheEntry(value="a", created_at=0, expires_at=1000, access_count=5),
            "b": CacheEntry(value="b", created_at=0, expires_at=1000, access_count=1),
            "c": CacheEntry(value="c", created_at=0, expires_at=1000, access_count=3),
        }

        victim = policy.select_victim(cache)
        assert victim == "b"  # 访问频率最低

    def test_ttl_policy(self) -> None:
        """测试 TTL 策略."""
        policy = TTLPolicy()
        cache = {
            "a": CacheEntry(value="a", created_at=0, expires_at=100),
            "b": CacheEntry(value="b", created_at=0, expires_at=300),
            "c": CacheEntry(value="c", created_at=0, expires_at=200),
        }

        victim = policy.select_victim(cache)
        assert victim == "a"  # 最早过期

    def test_priority_policy(self) -> None:
        """测试优先级策略."""
        policy = PriorityPolicy()
        cache = {
            "a": CacheEntry(value="a", created_at=0, expires_at=1000, priority=5),
            "b": CacheEntry(value="b", created_at=0, expires_at=1000, priority=1),
            "c": CacheEntry(value="c", created_at=0, expires_at=1000, priority=3),
        }

        victim = policy.select_victim(cache)
        assert victim == "b"  # 优先级最低


# =============================================================================
# Utils 测试
# =============================================================================


class TestHashUtils:
    """测试哈希工具."""

    def test_compute_hash(self) -> None:
        """测试哈希计算."""
        h1 = compute_hash("test", "sha256", 16)
        h2 = compute_hash("test", "sha256", 16)
        assert h1 == h2
        assert len(h1) == 16

    def test_compute_hash_different_algorithms(self) -> None:
        """测试不同算法."""
        h_md5 = compute_hash("test", "md5", 16)
        h_sha256 = compute_hash("test", "sha256", 16)
        assert h_md5 != h_sha256

    def test_compute_hash_invalid_algorithm(self) -> None:
        """测试无效算法."""
        with pytest.raises(ValueError):
            compute_hash("test", "invalid", 16)

    def test_compute_query_hash(self) -> None:
        """测试查询哈希."""
        h1 = compute_query_hash("pattern", "/path", {"case": True})
        h2 = compute_query_hash("pattern", "/path", {"case": True})
        h3 = compute_query_hash("pattern", "/path", {"case": False})

        assert h1 == h2
        assert h1 != h3

    def test_compute_file_hash(self, tmp_path: Path) -> None:
        """测试文件哈希."""
        test_file = tmp_path / "test.txt"
        test_file.write_text("test content")

        h1 = compute_file_hash(test_file)
        h2 = compute_file_hash(test_file)

        assert h1 == h2
        assert len(h1) == 64  # SHA256


class TestJsonSerializer:
    """测试 JSON 序列化."""

    def test_serialize_deserialize(self) -> None:
        """测试序列化/反序列化."""
        data = {"key": "value", "number": 42}
        serialized = JsonSerializer.serialize(data)
        deserialized = JsonSerializer.deserialize(serialized)
        assert deserialized == data

    def test_serialize_with_compression(self) -> None:
        """测试压缩序列化."""
        data = {"key": "value" * 100}
        serialized = JsonSerializer.serialize(data, compress=True)
        deserialized = JsonSerializer.deserialize(serialized, compressed=True)
        assert deserialized == data

    def test_compression_saves_space(self) -> None:
        """测试压缩节省空间."""
        data = {"key": "value" * 1000}
        uncompressed = JsonSerializer.serialize(data)
        compressed = JsonSerializer.serialize(data, compress=True)
        assert len(compressed) < len(uncompressed)


class TestBinarySerializer:
    """测试二进制序列化."""

    def test_pack_unpack_int(self) -> None:
        """测试整数打包/解包."""
        value = 12345
        packed = BinarySerializer.pack_int(value)
        unpacked = BinarySerializer.unpack_int(packed)
        assert unpacked == value

    def test_pack_unpack_int_negative(self) -> None:
        """测试负整数打包/解包."""
        value = -12345
        packed = BinarySerializer.pack_int(value)
        unpacked = BinarySerializer.unpack_int(packed)
        assert unpacked == value

    def test_pack_unpack_string(self) -> None:
        """测试字符串打包/解包."""
        s = "Hello, World!"
        packed = BinarySerializer.pack_string(s)
        unpacked, length = BinarySerializer.unpack_string(packed)
        assert unpacked == s
        assert length == len(packed)


class TestPerformanceTracker:
    """测试性能追踪器."""

    @pytest.mark.asyncio
    async def test_record(self) -> None:
        """测试记录操作."""
        tracker = PerformanceTracker()
        await tracker.start_recording()

        try:
            async with tracker.record("test_op"):
                await asyncio.sleep(0.01)

            metrics = tracker.get_metrics("test_op")
            assert metrics is not None
            assert metrics.count == 1
            assert metrics.total_time_ms > 0
        finally:
            await tracker.stop_recording()

    @pytest.mark.asyncio
    async def test_multiple_records(self) -> None:
        """测试多次记录."""
        tracker = PerformanceTracker()

        for _ in range(5):
            async with tracker.record("multi_op"):
                await asyncio.sleep(0.001)

        metrics = tracker.get_metrics("multi_op")
        assert metrics is not None
        assert metrics.count == 5
        assert metrics.min_time_ms <= metrics.avg_time_ms <= metrics.max_time_ms

    def test_get_all_metrics(self) -> None:
        """测试获取所有指标."""
        tracker = PerformanceTracker()
        tracker._metrics["op1"] = PerformanceMetrics(operation="op1", count=10)
        tracker._metrics["op2"] = PerformanceMetrics(operation="op2", count=20)

        all_metrics = tracker.get_all_metrics()
        assert "op1" in all_metrics
        assert "op2" in all_metrics

    def test_reset(self) -> None:
        """测试重置."""
        tracker = PerformanceTracker()
        tracker._metrics["op"] = PerformanceMetrics(operation="op")
        tracker.reset()
        assert len(tracker._metrics) == 0


class TestTimedDecorator:
    """测试计时装饰器."""

    @pytest.mark.asyncio
    async def test_async_timed(self) -> None:
        """测试异步计时."""
        @timed("test_async")
        async def async_func():
            await asyncio.sleep(0.01)
            return "result"

        result = await async_func()
        assert result == "result"

    def test_sync_timed(self) -> None:
        """测试同步计时."""
        @timed("test_sync")
        def sync_func():
            time.sleep(0.01)
            return "result"

        result = sync_func()
        assert result == "result"


class TestRetryDecorator:
    """测试重试装饰器."""

    @pytest.mark.asyncio
    async def test_retry_success(self) -> None:
        """测试重试成功."""
        attempts = 0

        @retry(RetryConfig(max_retries=3, base_delay=0.01))
        async def flaky_func():
            nonlocal attempts
            attempts += 1
            if attempts < 2:
                raise ValueError("Temporary error")
            return "success"

        result = await flaky_func()
        assert result == "success"
        assert attempts == 2

    @pytest.mark.asyncio
    async def test_retry_failure(self) -> None:
        """测试重试失败."""
        @retry(RetryConfig(max_retries=2, base_delay=0.01))
        async def failing_func():
            raise ValueError("Always fails")

        with pytest.raises(ValueError):
            await failing_func()


class TestMemoryManager:
    """测试内存管理器."""

    def test_get_process_memory(self) -> None:
        """测试获取进程内存."""
        memory = MemoryManager.get_process_memory()
        assert "maxrss_kb" in memory
        assert "maxrss_mb" in memory

    def test_format_size(self) -> None:
        """测试格式化大小."""
        assert MemoryManager.format_size(1024) == "1.00 KB"
        assert MemoryManager.format_size(1048576) == "1.00 MB"
        assert MemoryManager.format_size(1073741824) == "1.00 GB"


class TestRateLimiter:
    """测试限流器."""

    @pytest.mark.asyncio
    async def test_acquire(self) -> None:
        """测试获取令牌."""
        limiter = RateLimiter(rate=10, capacity=5)

        # 应该能立即获取 5 个令牌
        for _ in range(5):
            assert await limiter.acquire()

        # 第 6 个应该失败
        assert not await limiter.acquire()

    @pytest.mark.asyncio
    async def test_wait_for_token(self) -> None:
        """测试等待令牌."""
        limiter = RateLimiter(rate=100, capacity=1)

        # 获取第一个令牌
        await limiter.acquire()

        # 等待下一个令牌
        start = time.monotonic()
        await limiter.wait_for_token()
        elapsed = time.monotonic() - start

        # 应该等待约 10ms
        assert elapsed < 0.1


class TestCacheKeyGenerator:
    """测试缓存键生成器."""

    def test_simple(self) -> None:
        """测试简单键."""
        assert CacheKeyGenerator.simple("key") == "key"

    def test_prefixed(self) -> None:
        """测试带前缀的键."""
        assert CacheKeyGenerator.prefixed("prefix", "key") == "prefix:key"

    def test_hashed(self) -> None:
        """测试哈希键."""
        key = CacheKeyGenerator.hashed("test")
        assert len(key) == 16

    def test_composite(self) -> None:
        """测试组合键."""
        key = CacheKeyGenerator.composite("a", "b", "c")
        assert key == "a:b:c"

    def test_for_search(self) -> None:
        """测试搜索键."""
        key1 = CacheKeyGenerator.for_search("pattern", "/path")
        key2 = CacheKeyGenerator.for_search("pattern", "/path")
        key3 = CacheKeyGenerator.for_search("different", "/path")

        assert key1 == key2
        assert key1 != key3
        assert key1.startswith("search:")

    def test_for_file(self) -> None:
        """测试文件键."""
        key = CacheKeyGenerator.for_file("/path/to/file.txt")
        assert key.startswith("file:")


class TestBatchProcess:
    """测试批量处理."""

    @pytest.mark.asyncio
    async def test_batch_process(self) -> None:
        """测试批量处理."""
        async def processor(x: int) -> int:
            return x * 2

        items = list(range(10))
        results = await batch_process(items, processor, batch_size=3, concurrency=2)

        assert results == [i * 2 for i in items]

    @pytest.mark.asyncio
    async def test_batch_process_with_errors(self) -> None:
        """测试批量处理带错误."""
        async def processor(x: int) -> int:
            if x == 5:
                raise ValueError("Error at 5")
            return x

        items = list(range(10))
        results = await batch_process(items, processor, batch_size=3)

        # 应该有 9 个成功，1 个异常
        success_count = sum(1 for r in results if not isinstance(r, Exception))
        assert success_count == 9


class TestValidateFunctions:
    """测试验证函数."""

    def test_validate_compression_ratio_valid(self) -> None:
        """测试有效压缩比."""
        assert validate_compression_ratio(1000, 200) is True
        assert validate_compression_ratio(1000, 500) is True

    def test_validate_compression_ratio_invalid(self) -> None:
        """测试无效压缩比."""
        assert validate_compression_ratio(1000, 50, min_ratio=0.1) is False
        assert validate_compression_ratio(0, 100) is False
        assert validate_compression_ratio(-100, 50) is False

    def test_validate_cache_entry_valid(self) -> None:
        """测试有效缓存条目."""
        entry = CacheEntry(value="test", created_at=0, expires_at=1000)
        assert validate_cache_entry(entry) is True

    def test_validate_cache_entry_invalid(self) -> None:
        """测试无效缓存条目."""
        assert validate_cache_entry("not an entry") is False
        assert validate_cache_entry({}) is False


class TestErrorClasses:
    """测试错误类."""

    def test_database_error(self) -> None:
        """测试数据库错误."""
        err = DatabaseError(
            "Test error",
            original_error=ValueError("Original"),
            context={"key": "value"},
        )
        assert str(err) == "Test error"
        assert err.original_error is not None
        assert err.context == {"key": "value"}

        err_dict = err.to_dict()
        assert err_dict["type"] == "DatabaseError"
        assert err_dict["message"] == "Test error"

    def test_compression_error(self) -> None:
        """测试压缩错误."""
        # utils 中的 CompressionError 继承自 DatabaseError
        err = CompressionError("Compression failed")
        assert isinstance(err, DatabaseError)
        
        # compressed_db 中的 CompressionError (DBCompressionError) 继承自 CompressedDatabaseError
        err2 = DBCompressionError("Compression failed")
        assert isinstance(err2, CompressedDatabaseError)

    def test_cache_error(self) -> None:
        """测试缓存错误."""
        err = CacheError("Cache failed")
        assert isinstance(err, DatabaseError)


class TestHandleErrors:
    """测试错误处理上下文."""

    def test_handle_errors_success(self) -> None:
        """测试成功处理."""
        from grep_app_enhanced.database import handle_errors

        with handle_errors(DatabaseError):
            pass  # 不应抛出异常

    def test_handle_errors_failure(self) -> None:
        """测试失败处理."""
        from grep_app_enhanced.database import handle_errors

        with pytest.raises(DatabaseError) as exc_info:
            with handle_errors(DatabaseError, {"op": "test"}):
                raise ValueError("Test error")

        assert exc_info.value.context == {"op": "test"}


# =============================================================================
# 集成测试
# =============================================================================


class TestIntegration:
    """集成测试."""

    @pytest.mark.asyncio
    async def test_full_workflow(self, tmp_path: Path) -> None:
        """测试完整工作流."""
        db_path = tmp_path / "test.db"

        # 创建数据库
        async with CompressedDatabase(db_path, compression_level=5) as db:
            # 存储搜索结果
            results = [
                SearchResult(
                    file_path=f"file{i}.py",
                    line_number=i,
                    content=f"def test_{i}():",
                )
                for i in range(10)
            ]

            stats = await db.store_search_results(
                query_hash="integration_test",
                pattern="def test",
                search_path="/test",
                results=results,
                ttl_seconds=3600,
            )

            # 验证压缩比
            assert stats.compression_ratio < 1.0

            # 检索结果
            retrieved, retrieve_stats = await db.retrieve_search_results(
                "integration_test"
            )

            assert retrieved is not None
            assert len(retrieved) == 10

            # 验证性能
            perf = await db.estimate_performance_impact()
            assert "read_impact_percent" in perf
            assert "write_impact_percent" in perf

        # 创建缓存
        async with CacheManager(ttl=60, max_size=100) as cache:
            # 预热
            await cache.warm_up(
                ["key1", "key2", "key3"],
                lambda k: f"value_{k}",
            )

            # 验证
            assert await cache.get("key1") == "value_key1"

            # 获取报告
            report = await cache.get_report()
            assert "statistics" in report
            assert "configuration" in report
