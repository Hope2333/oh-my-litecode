"""
测试三层缓存和智能降级模块.

本测试模块验证：
- 三层缓存搜索功能
- 智能降级策略
- 缓存命中率
- 降级延迟
- 性能监控

Example:
    ```bash
    # 运行测试
    pytest tests/test_three_layer_cache.py -v

    # 运行特定测试
    pytest tests/test_three_layer_cache.py::test_three_layer_cache_search -v
    ```
"""

from __future__ import annotations

import asyncio
import tempfile
import time
from pathlib import Path
from typing import Any

import pytest

from grep_app_enhanced.search import (
    RemoteSearch,
    FallbackStrategy,
    FallbackConfig,
    ThreeLayerCacheStats,
    CircuitBreaker,
    PathwayHealth,
)
from grep_app_enhanced.search.remote_search import CacheLayer


class TestThreeLayerCache:
    """三层缓存测试类."""

    @pytest.fixture
    async def remote_search(self):
        """创建 RemoteSearch 测试实例."""
        with tempfile.TemporaryDirectory() as tmpdir:
            db_path = Path(tmpdir) / "test_cache.db"
            git_cache_dir = Path(tmpdir) / "git_cache"

            search = RemoteSearch(
                token=None,
                use_cache=True,
                db_path=db_path,
                git_cache_dir=git_cache_dir,
            )
            await search.initialize()
            yield search
            await search.close()

    @pytest.mark.asyncio
    async def test_initialization(self, remote_search: RemoteSearch):
        """测试三层缓存初始化."""
        assert remote_search._cache is not None, "L1 内存缓存未初始化"
        assert remote_search._db is not None, "L1 SQLite 缓存未初始化"
        assert remote_search.git_cache_dir is not None, "L2 Git 缓存目录未设置"

    @pytest.mark.asyncio
    async def test_three_layer_stats_initial(self, remote_search: RemoteSearch):
        """测试初始统计状态."""
        stats = remote_search.get_three_layer_stats()
        assert stats.l1_hits == 0
        assert stats.l1_misses == 0
        assert stats.l2_hits == 0
        assert stats.l2_misses == 0
        assert stats.l3_queries == 0

    @pytest.mark.asyncio
    async def test_cache_key_computation(self, remote_search: RemoteSearch):
        """测试缓存键计算."""
        key1 = remote_search._compute_cache_key(
            pattern="test",
            repo="owner/repo",
            ref="HEAD",
            path="",
            platform="github",
        )
        key2 = remote_search._compute_cache_key(
            pattern="test",
            repo="owner/repo",
            ref="HEAD",
            path="",
            platform="github",
        )
        key3 = remote_search._compute_cache_key(
            pattern="different",
            repo="owner/repo",
            ref="HEAD",
            path="",
            platform="github",
        )

        assert key1 == key2, "相同参数应产生相同缓存键"
        assert key1 != key3, "不同参数应产生不同缓存键"
        assert len(key1) == 64, "缓存键应为 SHA256 哈希"

    @pytest.mark.asyncio
    async def test_stats_to_dict(self, remote_search: RemoteSearch):
        """测试统计数据转换."""
        stats = ThreeLayerCacheStats(
            l1_hits=80,
            l1_misses=20,
            l2_hits=10,
            l2_misses=5,
            l3_queries=25,
            total_time_ms=150.5,
            cache_fill_backs=15,
        )

        stats_dict = stats.to_dict()
        assert stats_dict["l1_hits"] == 80
        assert stats_dict["l1_hit_rate"] == 0.8
        assert stats_dict["overall_hit_rate"] == 0.9
        assert stats_dict["cache_fill_backs"] == 15


class TestIntelligentFallback:
    """智能降级测试类."""

    @pytest.fixture
    async def fallback_strategy(self):
        """创建 FallbackStrategy 测试实例."""
        config = FallbackConfig(
            max_retries=2,
            retry_delay_ms=50,
            timeout_ms=5000,
            health_check_interval_ms=1000,
        )
        strategy = FallbackStrategy(config=config)
        await strategy.initialize()
        yield strategy
        await strategy.close()

    @pytest.mark.asyncio
    async def test_fallback_initialization(self, fallback_strategy: FallbackStrategy):
        """测试降级策略初始化."""
        assert fallback_strategy._running is True
        assert len(fallback_strategy._metrics) > 0
        assert len(fallback_strategy._circuit_breakers) > 0

    @pytest.mark.asyncio
    async def test_pathway_metrics(self, fallback_strategy: FallbackStrategy):
        """测试通路指标."""
        metrics = fallback_strategy.get_metrics("api")
        assert metrics is not None
        assert metrics.pathway_id == "api"

    @pytest.mark.asyncio
    async def test_healthy_pathways(self, fallback_strategy: FallbackStrategy):
        """测试健康通路获取."""
        healthy = fallback_strategy.get_healthy_pathways()
        assert len(healthy) > 0

    @pytest.mark.asyncio
    async def test_best_pathway(self, fallback_strategy: FallbackStrategy):
        """测试最佳通路选择."""
        best = fallback_strategy.get_best_pathway()
        assert best in fallback_strategy.default_fallback_chain

    @pytest.mark.asyncio
    async def test_execute_with_fallback_success(self, fallback_strategy: FallbackStrategy):
        """测试成功执行（无需降级）."""
        async def success_func():
            return {"result": "success"}

        result = await fallback_strategy.execute_with_fallback(
            success_func,
            pathway_id="test_pathway",
        )

        assert result.success is True
        assert result.result == {"result": "success"}
        assert result.pathway_used == "test_pathway"
        assert result.fallback_level.value == 0

    @pytest.mark.asyncio
    async def test_execute_with_fallback_failure(self, fallback_strategy: FallbackStrategy):
        """测试失败执行（触发降级）."""
        async def fail_func():
            raise Exception("Simulated failure")

        async def fallback_func():
            return {"result": "fallback_success"}

        result = await fallback_strategy.execute_with_fallback(
            fail_func,
            fallback_chain=[fallback_func],
            pathway_id="test_pathway",
            max_retries=0,  # 不重试，直接降级
        )

        # 应该触发降级
        assert result.success is True
        assert result.result == {"result": "fallback_success"}
        assert result.fallback_level.value >= 1

    @pytest.mark.asyncio
    async def test_circuit_breaker(self):
        """测试熔断器功能."""
        cb = CircuitBreaker(failure_threshold=3, timeout_ms=1000)

        # 初始状态应为 closed
        assert cb.state == "closed"
        assert cb.can_execute() is True

        # 记录失败直到熔断
        for _ in range(3):
            cb.record_failure()

        assert cb.state == "open"
        assert cb.can_execute() is False

        # 记录成功应重置
        cb.record_success()
        assert cb.state == "closed"
        assert cb.can_execute() is True

    @pytest.mark.asyncio
    async def test_pathway_health(self):
        """测试通路健康状态."""
        from grep_app_enhanced.search.intelligent_fallback import PathwayMetrics

        metrics = PathwayMetrics(pathway_id="test")

        # 初始状态
        assert metrics.get_health() == PathwayHealth.UNKNOWN

        # 记录成功
        metrics.record_success(100.0)
        assert metrics.get_health() == PathwayHealth.HEALTHY

        # 记录多次失败
        for _ in range(6):
            metrics.record_failure("error")
        assert metrics.get_health() == PathwayHealth.UNHEALTHY

    @pytest.mark.asyncio
    async def test_performance_report(self, fallback_strategy: FallbackStrategy):
        """测试性能报告."""
        report = fallback_strategy.get_performance_report()

        assert "pathways" in report
        assert "best_pathway" in report
        assert "healthy_pathways" in report
        assert "timestamp" in report


class TestCachePerformance:
    """缓存性能测试类."""

    @pytest.fixture
    async def remote_search_with_data(self):
        """创建带测试数据的 RemoteSearch 实例."""
        with tempfile.TemporaryDirectory() as tmpdir:
            db_path = Path(tmpdir) / "test_cache.db"
            git_cache_dir = Path(tmpdir) / "git_cache"

            search = RemoteSearch(
                token=None,
                use_cache=True,
                db_path=db_path,
                git_cache_dir=git_cache_dir,
            )
            await search.initialize()

            # 预填充一些测试数据
            from grep_app_enhanced import SearchResult

            test_results = [
                SearchResult(
                    file_path="test.py",
                    line_number=1,
                    content="def test():",
                ),
                SearchResult(
                    file_path="test.py",
                    line_number=2,
                    content="    pass",
                ),
            ]

            cache_key = search._compute_cache_key(
                pattern="test",
                repo="owner/repo",
                ref="HEAD",
                path="",
                platform="github",
            )

            # 写入 L1 内存缓存
            if search._cache:
                await search._cache.set(cache_key, test_results, ttl=3600)

            # 写入 L1 SQLite 缓存
            if search._db:
                query_hash = cache_key[:32]
                await search._db.store_search_results(
                    query_hash=query_hash,
                    pattern="owner/repo",
                    search_path="/",
                    results=test_results,
                    ttl_seconds=3600,
                )

            yield search
            await search.close()

    @pytest.mark.asyncio
    async def test_l1_memory_cache_hit(self, remote_search_with_data: RemoteSearch):
        """测试 L1 内存缓存命中."""
        cache_key = remote_search_with_data._compute_cache_key(
            pattern="test",
            repo="owner/repo",
            ref="HEAD",
            path="",
            platform="github",
        )

        results, elapsed = await remote_search_with_data._query_l1(cache_key)

        assert results is not None
        assert len(results) == 2
        assert elapsed < 10  # 内存缓存应该非常快 (<10ms)
        assert remote_search_with_data._three_layer_stats.l1_hits == 1

    @pytest.mark.asyncio
    async def test_l1_sqlite_cache_hit(self, remote_search_with_data: RemoteSearch):
        """测试 L1 SQLite 缓存命中."""
        import hashlib

        # 使用不同的缓存键来测试 SQLite 缓存
        cache_key = remote_search_with_data._compute_cache_key(
            pattern="sqlite_test",
            repo="owner/repo2",
            ref="HEAD",
            path="",
            platform="github",
        )

        # 先写入 SQLite
        from grep_app_enhanced import SearchResult

        test_results = [
            SearchResult(
                file_path="sqlite_test.py",
                line_number=1,
                content="def sqlite_test():",
            ),
        ]

        if remote_search_with_data._db:
            # 使用与 _query_l1 相同的哈希计算方式
            query_hash = hashlib.sha256(cache_key.encode()).hexdigest()[:32]
            await remote_search_with_data._db.store_search_results(
                query_hash=query_hash,
                pattern="owner/repo2",
                search_path="/",
                results=test_results,
                ttl_seconds=3600,
            )

        # 查询（应该命中 SQLite 缓存）
        results, elapsed = await remote_search_with_data._query_l1(cache_key)

        assert results is not None, "SQLite 缓存应该命中"
        assert len(results) == 1
        assert elapsed < 100  # SQLite 缓存应该较快 (<100ms)

    @pytest.mark.asyncio
    async def test_cache_fill_back(self, remote_search_with_data: RemoteSearch):
        """测试缓存回填功能."""
        from grep_app_enhanced import SearchResult
        from grep_app_enhanced.search.remote_search import RemoteSearchConfig

        test_results = [
            SearchResult(
                file_path="fill_back_test.py",
                line_number=1,
                content="def fill_back_test():",
            ),
        ]

        config = RemoteSearchConfig(
            repo="owner/repo",
            platform="github",
            cache_ttl=3600,
        )

        cache_key = remote_search_with_data._compute_cache_key(
            pattern="fill_back",
            repo="owner/repo",
            ref="HEAD",
            path="",
            platform="github",
        )

        # 执行回填
        await remote_search_with_data._fill_back_cache(cache_key, test_results, config)

        # 验证回填到内存缓存
        if remote_search_with_data._cache:
            cached = await remote_search_with_data._cache.get(cache_key)
            assert cached is not None
            assert len(cached) == 1

    @pytest.mark.asyncio
    async def test_l1_hit_rate_target(self, remote_search_with_data: RemoteSearch):
        """测试 L1 命中率目标 (>80%)."""
        # 模拟多次查询
        for i in range(10):
            cache_key = remote_search_with_data._compute_cache_key(
                pattern=f"test{i}",
                repo="owner/repo",
                ref="HEAD",
                path="",
                platform="github",
            )

            # 先写入
            from grep_app_enhanced import SearchResult
            test_results = [
                SearchResult(
                    file_path=f"test{i}.py",
                    line_number=1,
                    content=f"def test{i}():",
                ),
            ]
            if remote_search_with_data._cache:
                await remote_search_with_data._cache.set(cache_key, test_results, ttl=3600)

        # 查询 10 次
        for i in range(10):
            cache_key = remote_search_with_data._compute_cache_key(
                pattern=f"test{i}",
                repo="owner/repo",
                ref="HEAD",
                path="",
                platform="github",
            )
            await remote_search_with_data._query_l1(cache_key)

        stats = remote_search_with_data.get_three_layer_stats()
        assert stats.l1_hit_rate >= 0.8, f"L1 命中率应 >= 80%, 实际：{stats.l1_hit_rate:.2%}"


class TestFallbackLatency:
    """降级延迟测试类."""

    @pytest.mark.asyncio
    async def test_fallback_latency_target(self):
        """测试降级延迟目标 (<100ms)."""
        config = FallbackConfig(
            max_retries=0,
            retry_delay_ms=10,
            timeout_ms=1000,
        )
        strategy = FallbackStrategy(config=config)
        await strategy.initialize()

        try:
            # 模拟快速失败和降级
            async def slow_fail():
                await asyncio.sleep(0.05)  # 50ms
                raise Exception("fail")

            async def fast_fallback():
                return {"result": "fast"}

            start = time.perf_counter()
            result = await strategy.execute_with_fallback(
                slow_fail,
                fallback_chain=[fast_fallback],
                pathway_id="latency_test",
            )
            elapsed = (time.perf_counter() - start) * 1000

            # 总延迟应该 < 100ms
            assert elapsed < 100, f"降级延迟应 < 100ms, 实际：{elapsed:.2f}ms"
            assert result.success is True

        finally:
            await strategy.close()


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
