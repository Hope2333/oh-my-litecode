"""
Pathway Manager 模块测试.

测试 PathwayManager 及其相关类的功能.

Usage:
    pytest tests/test_pathway_manager.py -v

Note:
    部分测试需要网络连接和有效的 GITHUB_TOKEN.
    无网络测试会自动跳过外部依赖.

Author:
    Oh My LiteCode Team
"""

from __future__ import annotations

import os
import tempfile
from pathlib import Path

import pytest

from grep_app_enhanced.remote import (
    Checkpoint,
    GitClient,
    PathwayManager,
    PathwayStatus,
    PathwayType,
    PerformanceStats,
    PlatformType,
    SearchRequest,
    SearchResponse,
)
from grep_app_enhanced.remote.crawler import RateLimiter, RobotsParser


class TestPathwayType:
    """测试 PathwayType 枚举."""

    def test_pathway_values(self) -> None:
        """测试通路类型值."""
        assert PathwayType.GH_CLI.value == "gh_cli"
        assert PathwayType.API.value == "api"
        assert PathwayType.CRAWLER.value == "crawler"
        assert PathwayType.GIT_CLONE.value == "git_clone"
        assert PathwayType.HTTP_FALLBACK.value == "http_fallback"


class TestPlatformType:
    """测试 PlatformType 枚举."""

    def test_platform_values(self) -> None:
        """测试平台类型值."""
        assert PlatformType.GITHUB.value == "github"
        assert PlatformType.GITLAB.value == "gitlab"
        assert PlatformType.GITEE.value == "gitee"
        assert PlatformType.GENERIC.value == "generic"


class TestPathwayStatus:
    """测试 PathwayStatus 数据类."""

    def test_default_values(self) -> None:
        """测试默认值."""
        status = PathwayStatus(pathway_type=PathwayType.GH_CLI)

        assert status.available is True
        assert status.authenticated is False
        assert status.success_count == 0
        assert status.failure_count == 0

    def test_success_rate(self) -> None:
        """测试成功率计算."""
        status = PathwayStatus(
            pathway_type=PathwayType.GH_CLI,
            success_count=8,
            failure_count=2,
        )

        assert status.success_rate == 0.8

    def test_success_rate_zero_total(self) -> None:
        """测试零总数时的成功率."""
        status = PathwayStatus(pathway_type=PathwayType.GH_CLI)
        assert status.success_rate == 1.0

    def test_is_rate_limited(self) -> None:
        """测试速率限制检查."""
        status = PathwayStatus(
            pathway_type=PathwayType.API,
            rate_limit_remaining=5,
        )
        assert status.is_rate_limited is True

        status.rate_limit_remaining = 100
        assert status.is_rate_limited is False

    def test_to_dict(self) -> None:
        """测试转换为字典."""
        status = PathwayStatus(
            pathway_type=PathwayType.GH_CLI,
            available=True,
            authenticated=True,
            success_count=10,
        )

        data = status.to_dict()

        assert data["pathway_type"] == "gh_cli"
        assert data["available"] is True
        assert data["authenticated"] is True
        assert data["success_count"] == 10


class TestSearchRequest:
    """测试 SearchRequest 数据类."""

    def test_default_values(self) -> None:
        """测试默认值."""
        request = SearchRequest(pattern="test", repo="owner/repo")

        assert request.pattern == "test"
        assert request.repo == "owner/repo"
        assert request.platform == "github"
        assert request.max_results == 100
        assert request.allow_fallback is True


class TestSearchResponse:
    """测试 SearchResponse 数据类."""

    def test_default_values(self) -> None:
        """测试默认值."""
        response = SearchResponse()

        assert response.results == []
        assert response.pathway_used is None
        assert response.fallback_chain == []
        assert response.cache_hit is False

    def test_to_dict(self) -> None:
        """测试转换为字典."""
        from grep_app_enhanced import SearchResult

        response = SearchResponse(
            results=[
                SearchResult(
                    file_path="test.py",
                    line_number=10,
                    content="def test():",
                )
            ],
            pathway_used=PathwayType.GH_CLI,
            total_time_ms=150.5,
        )

        data = response.to_dict()

        assert data["result_count"] == 1
        assert data["pathway_used"] == "gh_cli"
        assert data["total_time_ms"] == 150.5
        assert data["cache_hit"] is False


class TestPerformanceStats:
    """测试 PerformanceStats 数据类."""

    def test_default_values(self) -> None:
        """测试默认值."""
        stats = PerformanceStats()

        assert stats.total_requests == 0
        assert stats.success_rate == 1.0

    def test_record_request(self) -> None:
        """测试记录请求."""
        stats = PerformanceStats()

        stats.record_request(
            success=True,
            response_time_ms=100.0,
            pathway="gh_cli",
        )
        stats.record_request(
            success=True,
            response_time_ms=200.0,
            pathway="api",
        )
        stats.record_request(
            success=False,
            response_time_ms=50.0,
            pathway="gh_cli",
        )

        assert stats.total_requests == 3
        assert stats.successful_requests == 2
        assert stats.failed_requests == 1
        assert stats.success_rate == pytest.approx(2 / 3, rel=0.01)

    def test_avg_response_time(self) -> None:
        """测试平均响应时间."""
        stats = PerformanceStats()

        stats.record_request(success=True, response_time_ms=100.0, pathway="api")
        stats.record_request(success=True, response_time_ms=200.0, pathway="api")
        stats.record_request(success=True, response_time_ms=300.0, pathway="api")

        assert stats.avg_response_time_ms == 200.0

    def test_to_dict(self) -> None:
        """测试转换为字典."""
        stats = PerformanceStats()
        stats.record_request(success=True, response_time_ms=100.0, pathway="gh_cli")

        data = stats.to_dict()

        assert data["total_requests"] == 1
        assert data["successful_requests"] == 1
        assert "pathway_usage" in data


class TestCheckpoint:
    """测试 Checkpoint 数据类."""

    def test_default_values(self) -> None:
        """测试默认值."""
        checkpoint = Checkpoint(request_hash="abc123")

        assert checkpoint.request_hash == "abc123"
        assert checkpoint.completed_repos == []
        assert checkpoint.state == "running"

    def test_to_dict(self) -> None:
        """测试转换为字典."""
        checkpoint = Checkpoint(
            request_hash="test123",
            completed_repos=["repo1", "repo2"],
            state="completed",
        )

        data = checkpoint.to_dict()

        assert data["request_hash"] == "test123"
        assert data["completed_repos"] == ["repo1", "repo2"]
        assert data["state"] == "completed"

    def test_from_dict(self) -> None:
        """测试从字典创建."""
        data = {
            "request_hash": "test456",
            "completed_repos": ["repo1"],
            "partial_results": [{"results": []}],
            "state": "paused",
        }

        checkpoint = Checkpoint.from_dict(data)

        assert checkpoint.request_hash == "test456"
        assert checkpoint.completed_repos == ["repo1"]
        assert checkpoint.state == "paused"


class TestRateLimiter:
    """测试 RateLimiter 类."""

    @pytest.mark.asyncio
    async def test_rate_limiting(self) -> None:
        """测试速率限制."""
        limiter = RateLimiter(rate=100.0, burst=10)

        # 突发请求应该立即完成
        start = __import__("time").time()
        for _ in range(5):
            await limiter.acquire()
        elapsed = __import__("time").time() - start

        # 5 个请求在突发容量内应该很快
        assert elapsed < 0.1

    @pytest.mark.asyncio
    async def test_rate_exhaustion(self) -> None:
        """测试速率耗尽."""
        limiter = RateLimiter(rate=10.0, burst=2)

        # 耗尽突发容量
        await limiter.acquire()
        await limiter.acquire()

        # 下一个请求应该等待
        start = __import__("time").time()
        await limiter.acquire()
        elapsed = __import__("time").time() - start

        # 应该等待至少 0.05 秒
        assert elapsed >= 0.05

    def test_reset(self) -> None:
        """测试重置."""
        limiter = RateLimiter(rate=10.0, burst=5)
        limiter._tokens = 0

        limiter.reset()

        assert limiter._tokens == 5.0


class TestRobotsParser:
    """测试 RobotsParser 类."""

    def test_parse_simple_rules(self) -> None:
        """测试解析简单规则."""
        parser = RobotsParser()

        content = """
User-agent: *
Disallow: /private/
Allow: /public/
"""
        parser._parse(content)

        assert parser.can_fetch("https://example.com/public/file.txt") is True
        assert parser.can_fetch("https://example.com/private/file.txt") is False

    def test_parse_specific_agent(self) -> None:
        """测试解析特定 User-Agent 规则."""
        parser = RobotsParser(user_agent="grep-app-enhanced")

        content = """
User-agent: grep-app-enhanced
Disallow: /api/

User-agent: *
Disallow: /admin/
"""
        parser._parse(content)

        # 特定规则优先
        assert parser.can_fetch("https://example.com/api/test") is False

    def test_empty_rules(self) -> None:
        """测试空规则."""
        parser = RobotsParser()
        parser._parse("")

        # 没有规则时应该允许所有
        assert parser.can_fetch("https://example.com/anything") is True

    def test_pattern_matching(self) -> None:
        """测试模式匹配."""
        parser = RobotsParser()

        content = """
User-agent: *
Disallow: /tmp$
"""
        parser._parse(content)

        # $ 表示精确匹配
        assert parser.can_fetch("https://example.com/tmp") is False
        assert parser.can_fetch("https://example.com/tmp/file") is True


class TestPathwayManager:
    """测试 PathwayManager 类."""

    @pytest.fixture
    def manager(self) -> PathwayManager:
        """创建 PathwayManager 实例."""
        return PathwayManager(
            token=os.environ.get("GITHUB_TOKEN"),
            cache_enabled=True,
            max_concurrent=2,
        )

    def test_initialization(self, manager: PathwayManager) -> None:
        """测试初始化."""
        assert manager.platform == "github"
        assert manager.cache_enabled is True
        assert manager.max_concurrent == 2

    @pytest.mark.asyncio
    async def test_context_manager(self, manager: PathwayManager) -> None:
        """测试异步上下文管理器."""
        async with manager:
            assert manager._initialized is True

        # 退出后应该关闭
        assert manager._initialized is False

    @pytest.mark.asyncio
    async def test_compute_cache_key(self, manager: PathwayManager) -> None:
        """测试缓存键计算."""
        request = SearchRequest(
            pattern="test",
            repo="owner/repo",
            platform="github",
        )

        key1 = manager._compute_cache_key(request)
        key2 = manager._compute_cache_key(request)

        assert key1 == key2
        assert len(key1) == 64  # SHA256 哈希长度

    @pytest.mark.asyncio
    async def test_cache_operations(self, manager: PathwayManager) -> None:
        """测试缓存操作."""
        await manager.initialize()

        key = "test_key"
        value = {"data": "test"}

        # 设置缓存
        await manager._set_cache(key, value)

        # 获取缓存
        cached = await manager._check_cache(key)
        assert cached == value

        # 清理
        await manager.close()

    @pytest.mark.asyncio
    async def test_select_pathway(self, manager: PathwayManager) -> None:
        """测试通路选择."""
        await manager.initialize()

        # 默认应该选择最高优先级的可用通路
        pathway = await manager._select_pathway()

        assert isinstance(pathway, PathwayType)

        # 清理
        await manager.close()

    @pytest.mark.asyncio
    async def test_get_pathway_status(self, manager: PathwayManager) -> None:
        """测试获取通路状态."""
        await manager.initialize()

        statuses = manager.get_pathway_status()

        assert "gh_cli" in statuses
        assert "api" in statuses
        assert "crawler" in statuses

        # 清理
        await manager.close()

    @pytest.mark.asyncio
    async def test_get_performance_stats(self, manager: PathwayManager) -> None:
        """测试获取性能统计."""
        await manager.initialize()

        stats = manager.get_performance_stats()

        assert "total_requests" in stats
        assert "success_rate" in stats
        assert "avg_response_time_ms" in stats

        # 清理
        await manager.close()

    @pytest.mark.asyncio
    async def test_merge_results(self, manager: PathwayManager) -> None:
        """测试结果合并."""
        from grep_app_enhanced import SearchResult

        results1 = [
            SearchResult(file_path="a.py", line_number=1, content="line1"),
            SearchResult(file_path="b.py", line_number=2, content="line2"),
        ]
        results2 = [
            SearchResult(file_path="a.py", line_number=1, content="line1"),  # 重复
            SearchResult(file_path="c.py", line_number=3, content="line3"),
        ]

        # 合并并去重
        merged = manager.merge_results([results1, results2], deduplicate=True)

        assert len(merged) == 3  # 去重后应该是 3 个

        # 按文件路径排序
        merged_sorted = manager.merge_results(
            [results1, results2], deduplicate=True, sort_by="file_path"
        )
        assert merged_sorted[0].file_path == "a.py"
        assert merged_sorted[1].file_path == "b.py"
        assert merged_sorted[2].file_path == "c.py"

    @pytest.mark.asyncio
    async def test_reset_pathway_status(self, manager: PathwayManager) -> None:
        """测试重置通路状态."""
        await manager.initialize()

        # 修改状态
        status = manager._pathway_statuses[PathwayType.GH_CLI]
        status.success_count = 10
        status.failure_count = 5

        # 重置
        await manager.reset_pathway_status(PathwayType.GH_CLI)

        status = manager._pathway_statuses[PathwayType.GH_CLI]
        assert status.success_count == 0
        assert status.failure_count == 0

        # 清理
        await manager.close()

    @pytest.mark.asyncio
    async def test_checkpoint_operations(
        self, manager: PathwayManager, tmp_path: Path
    ) -> None:
        """测试检查点操作."""
        manager.checkpoint_dir = tmp_path
        await manager.initialize()

        # 创建检查点
        checkpoint = Checkpoint(
            request_hash="test_hash",
            completed_repos=["repo1"],
            state="running",
        )
        manager._checkpoints["test_hash"] = checkpoint

        # 保存检查点
        await manager._save_checkpoints()

        # 验证文件存在
        checkpoint_file = tmp_path / "test_hash.json"
        assert checkpoint_file.exists()

        # 清空并重新加载
        manager._checkpoints.clear()
        await manager._load_checkpoints()

        assert "test_hash" in manager._checkpoints

        # 清理
        await manager.clear_checkpoints()
        await manager.close()

    @pytest.mark.asyncio
    @pytest.mark.skipif(
        not os.environ.get("GITHUB_TOKEN"),
        reason="需要 GITHUB_TOKEN",
    )
    async def test_search_basic(self, manager: PathwayManager) -> None:
        """测试基本搜索（需要网络）."""
        await manager.initialize()

        response = await manager.search(
            pattern="README",
            repo="git-fixtures/basic",
            max_results=5,
        )

        assert isinstance(response, SearchResponse)
        assert response.total_time_ms >= 0

        # 清理
        await manager.close()

    @pytest.mark.asyncio
    @pytest.mark.skipif(
        not os.environ.get("GITHUB_TOKEN"),
        reason="需要 GITHUB_TOKEN",
    )
    async def test_search_with_fallback(self, manager: PathwayManager) -> None:
        """测试带降级的搜索（需要网络）."""
        await manager.initialize()

        # 强制使用 API 通路
        response = await manager.search(
            pattern="TODO",
            repo="git-fixtures/basic",
            preferred_pathway=PathwayType.API,
            allow_fallback=True,
        )

        assert isinstance(response, SearchResponse)
        # 应该有通路使用记录
        assert response.pathway_used is not None or response.error is not None

        # 清理
        await manager.close()


class TestIntegration:
    """集成测试."""

    @pytest.mark.asyncio
    @pytest.mark.skipif(
        not os.environ.get("GITHUB_TOKEN"),
        reason="需要 GITHUB_TOKEN",
    )
    async def test_full_workflow(self) -> None:
        """测试完整工作流（需要网络）."""
        async with PathwayManager(token=os.environ.get("GITHUB_TOKEN")) as manager:
            # 搜索
            response = await manager.search(
                pattern="def main",
                repo="git-fixtures/basic",
                max_results=10,
            )

            # 验证响应
            assert response.total_time_ms >= 0
            assert response.fallback_chain is not None

            # 获取统计
            stats = manager.get_performance_stats()
            assert stats["total_requests"] >= 1

    @pytest.mark.asyncio
    async def test_git_client_integration(self, tmp_path: Path) -> None:
        """测试 Git 客户端集成（需要 git 安装）."""
        git = GitClient()

        # 检查 git 是否可用
        if not git.git_path:
            pytest.skip("git 未安装")

        # 克隆测试仓库
        repo_path = tmp_path / "test_repo"
        result = await git.clone_repository(
            url="https://github.com/git-fixtures/basic.git",
            dest=repo_path,
            depth=1,
        )

        assert result["success"] is True
        assert repo_path.exists()

        # 搜索
        results = await git.search_in_repo(
            repo_path=repo_path,
            pattern="package",
            max_results=5,
        )

        assert isinstance(results, list)

        # 获取文件内容
        content = await git.get_file_content(
            repo_path=repo_path,
            ref="HEAD:go/example.go",
        )

        assert len(content) > 0
