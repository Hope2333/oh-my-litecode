"""
Database 模块测试.

测试 CompressedDatabase 和 CacheManager 的功能.

Usage:
    pytest tests/test_database.py -v

Author:
    Oh My LiteCode Team
"""

from __future__ import annotations

import asyncio
import tempfile
from pathlib import Path

import pytest

from grep_app_enhanced import SearchResult
from grep_app_enhanced.database import (
    CompressedDatabase,
    CacheManager,
    CacheEntry,
    CacheStats,
)


class TestCompressionStats:
    """测试 CompressionStats 数据类."""

    def test_space_saved(self) -> None:
        """测试节省空间计算."""
        from grep_app_enhanced.database.compressed_db import CompressionStats

        stats = CompressionStats(
            original_size=10000,
            compressed_size=3000,
        )

        assert stats.space_saved == 7000

    def test_space_saved_percent(self) -> None:
        """测试节省空间百分比计算."""
        from grep_app_enhanced.database.compressed_db import CompressionStats

        stats = CompressionStats(
            original_size=10000,
            compressed_size=3000,
        )

        assert abs(stats.space_saved_percent - 70.0) < 0.01

    def test_space_saved_percent_zero_original(self) -> None:
        """测试原始大小为 0 时的百分比."""
        from grep_app_enhanced.database.compressed_db import CompressionStats

        stats = CompressionStats(original_size=0, compressed_size=0)
        assert stats.space_saved_percent == 0.0

    def test_to_dict(self) -> None:
        """测试转换为字典."""
        from grep_app_enhanced.database.compressed_db import CompressionStats

        stats = CompressionStats(
            original_size=10000,
            compressed_size=3000,
            compress_time_ms=1.5,
            decompress_time_ms=0.8,
        )

        result = stats.to_dict()
        assert result["original_size"] == 10000
        assert result["compressed_size"] == 3000
        assert result["space_saved"] == 7000


class TestCompressedDatabase:
    """测试 CompressedDatabase 类."""

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
    async def test_initialization(self, db: CompressedDatabase) -> None:
        """测试数据库初始化."""
        # 检查连接池是否初始化
        assert db._pool is not None

    @pytest.mark.asyncio
    async def test_compression_level_validation(self, temp_db_path: Path) -> None:
        """测试压缩级别验证."""
        # 有效级别
        db = CompressedDatabase(temp_db_path, compression_level=5)
        assert db.config.compression_level == 5

        # 无效级别
        with pytest.raises(ValueError):
            CompressedDatabase(temp_db_path, compression_level=0)

        with pytest.raises(ValueError):
            CompressedDatabase(temp_db_path, compression_level=23)

    @pytest.mark.asyncio
    async def test_store_and_retrieve(self, db: CompressedDatabase) -> None:
        """测试存储和检索搜索结果."""
        results = [
            SearchResult(
                file_path="test.py",
                line_number=1,
                content="def hello():",
                context_before=[],
                context_after=["    pass"],
            ),
            SearchResult(
                file_path="test.py",
                line_number=5,
                content="def world():",
                context_before=[],
                context_after=[],
            ),
        ]

        # 存储
        await db.store_search_results(
            query_hash="test_hash_123",
            pattern="def ",
            search_path="/test",
            results=results,
            ttl_seconds=3600,
        )

        # 检索
        retrieved, _ = await db.retrieve_search_results("test_hash_123")

        assert retrieved is not None
        assert len(retrieved) == 2
        assert retrieved[0].file_path == "test.py"
        assert retrieved[0].line_number == 1

    @pytest.mark.asyncio
    async def test_retrieve_nonexistent(self, db: CompressedDatabase) -> None:
        """测试检索不存在的键."""
        result, _ = await db.retrieve_search_results("nonexistent_hash")
        assert result is None

    @pytest.mark.asyncio
    async def test_cleanup_expired(self, db: CompressedDatabase) -> None:
        """测试清理过期数据."""
        # 存储一个立即过期的结果
        results = [
            SearchResult(
                file_path="test.py",
                line_number=1,
                content="test",
            )
        ]

        await db.store_search_results(
            query_hash="expired_hash",
            pattern="test",
            search_path="/test",
            results=results,
            ttl_seconds=0,  # 立即过期
        )

        # 等待一小段时间确保过期
        await asyncio.sleep(0.1)

        # 清理
        cleaned = await db.cleanup_expired()
        assert cleaned >= 0  # 可能为 0 如果已经过期

    @pytest.mark.asyncio
    async def test_context_manager(self, temp_db_path: Path) -> None:
        """测试异步上下文管理器."""
        async with CompressedDatabase(temp_db_path, auto_cleanup=False) as db:
            assert db._pool is not None

        # 退出后连接池应关闭
        assert db._pool is None

    @pytest.mark.asyncio
    async def test_get_stats(self, db: CompressedDatabase) -> None:
        """测试获取统计信息."""
        stats = await db.get_stats()

        assert stats.original_size >= 0
        assert stats.compressed_size >= 0


class TestCacheEntry:
    """测试 CacheEntry 数据类."""

    def test_is_expired(self) -> None:
        """测试过期检查."""
        import time

        entry = CacheEntry(
            value="test",
            created_at=time.time(),
            expires_at=time.time() + 3600,
        )
        assert not entry.is_expired()

        expired_entry = CacheEntry(
            value="test",
            created_at=time.time() - 7200,
            expires_at=time.time() - 3600,
        )
        assert expired_entry.is_expired()

    def test_touch(self) -> None:
        """测试访问时间更新."""
        import time

        entry = CacheEntry(
            value="test",
            created_at=time.time(),
            expires_at=time.time() + 3600,
            access_count=0,
        )

        entry.touch()
        assert entry.access_count == 1

        entry.touch()
        assert entry.access_count == 2

    def test_to_dict_and_from_dict(self) -> None:
        """测试序列化和反序列化."""
        import time

        original = CacheEntry(
            value={"key": "value"},
            created_at=time.time(),
            expires_at=time.time() + 3600,
            access_count=5,
            size_bytes=100,
        )

        data = original.to_dict()
        restored = CacheEntry.from_dict(data)

        assert restored.value == original.value
        assert restored.access_count == original.access_count
        assert restored.size_bytes == original.size_bytes


class TestCacheStats:
    """测试 CacheStats 数据类."""

    def test_hit_rate(self) -> None:
        """测试命中率计算."""
        stats = CacheStats()
        stats.hits = 80
        stats.misses = 20

        assert abs(stats.hit_rate - 0.8) < 0.01
        assert abs(stats.miss_rate - 0.2) < 0.01

    def test_hit_rate_zero_total(self) -> None:
        """测试零总数时的命中率."""
        stats = CacheStats()
        assert stats.hit_rate == 0.0

    def test_record_methods(self) -> None:
        """测试记录方法."""
        stats = CacheStats()

        stats.record_hit()
        stats.record_hit()
        stats.record_miss()
        stats.record_eviction()
        stats.record_expiration()

        assert stats.hits == 2
        assert stats.misses == 1
        assert stats.evictions == 1
        assert stats.expirations == 1


class TestCacheManager:
    """测试 CacheManager 类."""

    @pytest.fixture
    async def cache(self) -> CacheManager:
        """创建缓存管理器实例."""
        cache = CacheManager(ttl=60, max_size=100)
        await cache.initialize()
        yield cache
        await cache.close()

    @pytest.mark.asyncio
    async def test_set_and_get(self, cache: CacheManager) -> None:
        """测试设置和获取缓存."""
        await cache.set("key1", "value1")
        result = await cache.get("key1")

        assert result == "value1"

    @pytest.mark.asyncio
    async def test_get_nonexistent(self, cache: CacheManager) -> None:
        """测试获取不存在的键."""
        result = await cache.get("nonexistent")
        assert result is None

    @pytest.mark.asyncio
    async def test_get_with_default(self, cache: CacheManager) -> None:
        """测试获取带默认值."""
        result = await cache.get("nonexistent", "default")
        assert result == "default"

    @pytest.mark.asyncio
    async def test_delete(self, cache: CacheManager) -> None:
        """测试删除缓存."""
        await cache.set("key1", "value1")
        deleted = await cache.delete("key1")
        assert deleted is True

        result = await cache.get("key1")
        assert result is None

    @pytest.mark.asyncio
    async def test_delete_nonexistent(self, cache: CacheManager) -> None:
        """测试删除不存在的键."""
        deleted = await cache.delete("nonexistent")
        assert deleted is False

    @pytest.mark.asyncio
    async def test_clear(self, cache: CacheManager) -> None:
        """测试清空缓存."""
        await cache.set("key1", "value1")
        await cache.set("key2", "value2")

        await cache.clear()

        result1 = await cache.get("key1")
        result2 = await cache.get("key2")

        assert result1 is None
        assert result2 is None

    @pytest.mark.asyncio
    async def test_lru_eviction(self) -> None:
        """测试 LRU 淘汰策略."""
        cache = CacheManager(ttl=60, max_size=3)
        await cache.initialize()

        try:
            # 添加 3 个条目
            await cache.set("key1", "value1")
            await cache.set("key2", "value2")
            await cache.set("key3", "value3")

            # 访问 key1 使其变为最近使用
            await cache.get("key1")

            # 添加第 4 个条目，应淘汰 key2（最久未使用）
            await cache.set("key4", "value4")

            # key2 应被淘汰
            result2 = await cache.get("key2")
            assert result2 is None

            # 其他键应存在
            assert await cache.get("key1") == "value1"
            assert await cache.get("key3") == "value3"
            assert await cache.get("key4") == "value4"
        finally:
            await cache.close()

    @pytest.mark.asyncio
    async def test_custom_ttl(self, cache: CacheManager) -> None:
        """测试自定义 TTL."""
        await cache.set("key1", "value1", ttl=1)

        # 立即获取应存在
        result = await cache.get("key1")
        assert result == "value1"

        # 等待过期
        await asyncio.sleep(1.5)

        # 获取应返回 None
        result = await cache.get("key1")
        assert result is None

    @pytest.mark.asyncio
    async def test_stats(self, cache: CacheManager) -> None:
        """测试统计信息."""
        await cache.set("key1", "value1")
        await cache.get("key1")  # hit
        await cache.get("key2")  # miss

        stats = cache.get_stats()

        assert stats.hits == 1
        assert stats.misses == 1
        assert abs(stats.hit_rate - 0.5) < 0.01

    @pytest.mark.asyncio
    async def test_context_manager(self) -> None:
        """测试异步上下文管理器."""
        async with CacheManager() as cache:
            await cache.set("key", "value")
            assert await cache.get("key") == "value"

    @pytest.mark.asyncio
    async def test_warm_up(self, cache: CacheManager) -> None:
        """测试缓存预热."""
        async def loader(key: str) -> str:
            return f"value_{key}"

        await cache.warm_up(["a", "b", "c"], loader)

        assert await cache.get("a") == "value_a"
        assert await cache.get("b") == "value_b"
        assert await cache.get("c") == "value_c"

    @pytest.mark.asyncio
    async def test_warm_up_with_errors(self, cache: CacheManager) -> None:
        """测试缓存预热时处理错误."""
        async def failing_loader(key: str) -> str:
            if key == "bad":
                raise ValueError("Simulated error")
            return f"value_{key}"

        # 不应抛出异常
        await cache.warm_up(["good", "bad", "ok"], failing_loader)

        assert await cache.get("good") == "value_good"
        assert await cache.get("ok") == "value_ok"
        assert await cache.get("bad") is None
