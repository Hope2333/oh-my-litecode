"""
Search 模块测试.

测试 LocalSearch 和 RemoteSearch 的功能.

Usage:
    pytest tests/test_search.py -v

Author:
    Oh My LiteCode Team
"""

from __future__ import annotations

import os
import tempfile
from pathlib import Path

import pytest

from grep_app_enhanced import SearchResult
from grep_app_enhanced.search import LocalSearch, RemoteSearch
from grep_app_enhanced.search.local_search import SearchProgress
from grep_app_enhanced.search.remote_search import RemoteSearchConfig, SearchStatistics


class TestSearchResult:
    """测试 SearchResult 数据类."""

    def test_basic_creation(self) -> None:
        """测试基本创建."""
        result = SearchResult(
            file_path="test.py",
            line_number=42,
            content="def hello():",
        )

        assert result.file_path == "test.py"
        assert result.line_number == 42
        assert result.content == "def hello()"

    def test_with_context(self) -> None:
        """测试带上下文的创建."""
        result = SearchResult(
            file_path="test.py",
            line_number=5,
            content="    pass",
            context_before=["def test():"],
            context_after=["", "def other():"],
        )

        assert len(result.context_before) == 1
        assert len(result.context_after) == 2

    def test_with_match_positions(self) -> None:
        """测试带匹配位置的创建."""
        result = SearchResult(
            file_path="test.py",
            line_number=1,
            content="def hello():",
            match_start=0,
            match_end=3,
        )

        assert result.match_start == 0
        assert result.match_end == 3
        assert result.content[result.match_start:result.match_end] == "def"

    def test_to_dict(self) -> None:
        """测试转换为字典."""
        result = SearchResult(
            file_path="test.py",
            line_number=1,
            content="test",
            metadata={"key": "value"},
        )

        data = result.to_dict()

        assert data["file_path"] == "test.py"
        assert data["line_number"] == 1
        assert data["content"] == "test"
        assert data["metadata"]["key"] == "value"


class TestSearchConfig:
    """测试 SearchConfig 数据类."""

    def test_default_values(self) -> None:
        """测试默认值."""
        from grep_app_enhanced import SearchConfig

        config = SearchConfig(pattern="test")

        assert config.pattern == "test"
        assert config.path == "."
        assert config.max_results == 1000
        assert config.context_lines == 2
        assert config.use_regex is True
        assert config.case_sensitive is False

    def test_custom_values(self) -> None:
        """测试自定义值."""
        from grep_app_enhanced import SearchConfig

        config = SearchConfig(
            pattern="test",
            path="/src",
            include=["*.py"],
            exclude=["__pycache__"],
            max_results=50,
            context_lines=5,
            case_sensitive=True,
        )

        assert config.path == "/src"
        assert config.include == ["*.py"]
        assert config.exclude == ["__pycache__"]
        assert config.max_results == 50
        assert config.context_lines == 5
        assert config.case_sensitive is True


class TestSearchProgress:
    """测试 SearchProgress 数据类."""

    def test_default_values(self) -> None:
        """测试默认值."""
        progress = SearchProgress()

        assert progress.files_scanned == 0
        assert progress.files_matched == 0
        assert progress.total_matches == 0

    def test_to_dict(self) -> None:
        """测试转换为字典."""
        progress = SearchProgress(
            files_scanned=100,
            files_matched=10,
            total_matches=50,
            bytes_processed=10000,
            elapsed_seconds=1.5,
        )

        data = progress.to_dict()

        assert data["files_scanned"] == 100
        assert data["files_matched"] == 10
        assert data["total_matches"] == 50


class TestLocalSearch:
    """测试 LocalSearch 类."""

    @pytest.fixture
    def search(self) -> LocalSearch:
        """创建 LocalSearch 实例."""
        return LocalSearch(max_workers=2)

    @pytest.fixture
    def test_dir(self, tmp_path: Path) -> Path:
        """创建测试目录结构."""
        # 创建测试文件
        (tmp_path / "test1.py").write_text("""
def hello():
    print("Hello, World!")

def test_function():
    # TODO: implement this
    pass
""")

        (tmp_path / "test2.py").write_text("""
class MyClass:
    def __init__(self):
        self.value = 42

    def get_value(self):
        return self.value
""")

        # 创建子目录
        subdir = tmp_path / "subdir"
        subdir.mkdir()
        (subdir / "nested.py").write_text("""
def nested_function():
    return "nested"
""")

        # 创建应排除的文件
        cache_dir = tmp_path / "__pycache__"
        cache_dir.mkdir()
        (cache_dir / "test.pyc").write_text("binary")

        return tmp_path

    def test_initialization(self, search: LocalSearch) -> None:
        """测试初始化."""
        assert search.max_workers == 2
        assert search.context_lines == 2

    @pytest.mark.asyncio
    async def test_context_manager(self) -> None:
        """测试异步上下文管理器."""
        async with LocalSearch() as search:
            assert search._executor is not None

    @pytest.mark.asyncio
    async def test_search_basic(self, search: LocalSearch, test_dir: Path) -> None:
        """测试基本搜索."""
        results = await search.search(
            pattern="def ",
            path=str(test_dir),
            include=["*.py"],
        )

        assert len(results) > 0
        assert all("def " in r.content for r in results)

    @pytest.mark.asyncio
    async def test_search_regex(self, search: LocalSearch, test_dir: Path) -> None:
        """测试正则表达式搜索."""
        results = await search.search(
            pattern=r"def \w+\(\):",
            path=str(test_dir),
            include=["*.py"],
            use_regex=True,
        )

        assert len(results) > 0

    @pytest.mark.asyncio
    async def test_search_case_sensitive(self, search: LocalSearch, test_dir: Path) -> None:
        """测试区分大小写搜索."""
        # 不区分大小写（默认）
        results_insensitive = await search.search(
            pattern="DEF",
            path=str(test_dir),
            include=["*.py"],
            case_sensitive=False,
        )

        # 区分大小写
        results_sensitive = await search.search(
            pattern="DEF",
            path=str(test_dir),
            include=["*.py"],
            case_sensitive=True,
        )

        assert len(results_insensitive) > 0
        assert len(results_sensitive) == 0

    @pytest.mark.asyncio
    async def test_search_with_exclude(self, search: LocalSearch, test_dir: Path) -> None:
        """测试带排除的搜索."""
        results = await search.search(
            pattern=".*",
            path=str(test_dir),
            include=["*"],
            exclude=["__pycache__"],
        )

        # 不应包含 __pycache__ 中的文件
        assert not any("__pycache__" in r.file_path for r in results)

    @pytest.mark.asyncio
    async def test_search_max_results(self, search: LocalSearch, test_dir: Path) -> None:
        """测试最大结果数限制."""
        results = await search.search(
            pattern=".",
            path=str(test_dir),
            include=["*.py"],
            max_results=3,
        )

        assert len(results) <= 3

    @pytest.mark.asyncio
    async def test_search_with_context(self, search: LocalSearch, test_dir: Path) -> None:
        """测试带上下文的搜索."""
        search_with_context = LocalSearch(context_lines=3)

        results = await search_with_context.search(
            pattern="def hello",
            path=str(test_dir),
            include=["*.py"],
        )

        assert len(results) > 0
        # 应有上下文
        assert len(results[0].context_before) >= 0
        assert len(results[0].context_after) >= 0

    @pytest.mark.asyncio
    async def test_search_file(self, search: LocalSearch, test_dir: Path) -> None:
        """测试搜索单个文件."""
        test_file = test_dir / "test1.py"

        results = await search.search_file(
            pattern="def ",
            file_path=str(test_file),
        )

        assert len(results) > 0
        assert all(r.file_path == str(test_file) for r in results)

    @pytest.mark.asyncio
    async def test_search_nonexistent_path(self, search: LocalSearch) -> None:
        """测试搜索不存在的路径."""
        with pytest.raises(FileNotFoundError):
            await search.search(
                pattern="test",
                path="/nonexistent/path",
            )

    @pytest.mark.asyncio
    async def test_search_nonexistent_file(self, search: LocalSearch) -> None:
        """测试搜索不存在的文件."""
        with pytest.raises(FileNotFoundError):
            await search.search_file(
                pattern="test",
                file_path="/nonexistent/file.py",
            )

    @pytest.mark.asyncio
    async def test_search_stream(self, search: LocalSearch, test_dir: Path) -> None:
        """测试流式搜索."""
        results = []
        async for result in search.search_stream(
            pattern="def ",
            path=str(test_dir),
            include=["*.py"],
        ):
            results.append(result)

        assert len(results) > 0

    @pytest.mark.asyncio
    async def test_count_matches(self, search: LocalSearch, test_dir: Path) -> None:
        """测试统计匹配数."""
        stats = await search.count_matches(
            pattern="def ",
            path=str(test_dir),
            include=["*.py"],
        )

        assert stats["total_matches"] > 0
        assert stats["files_matched"] > 0
        assert isinstance(stats["by_file"], dict)

    @pytest.mark.asyncio
    async def test_get_progress(self, search: LocalSearch, test_dir: Path) -> None:
        """测试获取进度."""
        await search.search(
            pattern="def ",
            path=str(test_dir),
            include=["*.py"],
        )

        progress = search.get_progress()
        assert progress.files_scanned > 0


class TestRemoteSearchConfig:
    """测试 RemoteSearchConfig 数据类."""

    def test_default_values(self) -> None:
        """测试默认值."""
        config = RemoteSearchConfig(repo="owner/repo")

        assert config.repo == "owner/repo"
        assert config.platform == "github"
        assert config.ref == "HEAD"
        assert config.use_api is True
        assert config.use_cache is True

    def test_custom_values(self) -> None:
        """测试自定义值."""
        config = RemoteSearchConfig(
            repo="owner/repo",
            platform="gitlab",
            ref="main",
            path="src/",
            language="Python",
            use_api=False,
        )

        assert config.platform == "gitlab"
        assert config.ref == "main"
        assert config.path == "src/"
        assert config.language == "Python"
        assert config.use_api is False


class TestSearchStatistics:
    """测试 SearchStatistics 数据类."""

    def test_default_values(self) -> None:
        """测试默认值."""
        stats = SearchStatistics()

        assert stats.api_calls == 0
        assert stats.files_searched == 0
        assert stats.cache_hits == 0
        assert stats.cache_misses == 0

    def test_to_dict(self) -> None:
        """测试转换为字典."""
        stats = SearchStatistics(
            api_calls=5,
            files_searched=10,
            cache_hits=3,
            cache_misses=2,
            total_time_ms=1500.0,
        )

        data = stats.to_dict()

        assert data["api_calls"] == 5
        assert data["files_searched"] == 10
        assert data["total_time_ms"] == 1500.0


class TestRemoteSearch:
    """测试 RemoteSearch 类."""

    @pytest.fixture
    def remote_search(self) -> RemoteSearch:
        """创建 RemoteSearch 实例."""
        return RemoteSearch(
            token=os.environ.get("GITHUB_TOKEN"),
            use_cache=False,
        )

    def test_initialization(self, remote_search: RemoteSearch) -> None:
        """测试初始化."""
        assert remote_search.default_platform == "github"
        assert remote_search.use_cache is False

    @pytest.mark.asyncio
    async def test_context_manager(self) -> None:
        """测试异步上下文管理器."""
        async with RemoteSearch() as search:
            assert search._github is not None
            assert search._git is not None

    @pytest.mark.asyncio
    async def test_compute_cache_key(self, remote_search: RemoteSearch) -> None:
        """测试缓存键计算."""
        key1 = remote_search._compute_cache_key(
            pattern="test",
            repo="owner/repo",
            ref="main",
            path="src/",
            platform="github",
        )

        key2 = remote_search._compute_cache_key(
            pattern="test",
            repo="owner/repo",
            ref="main",
            path="src/",
            platform="github",
        )

        # 相同参数应产生相同键
        assert key1 == key2

        # 不同参数应产生不同键
        key3 = remote_search._compute_cache_key(
            pattern="other",
            repo="owner/repo",
            ref="main",
            path="src/",
            platform="github",
        )
        assert key1 != key3

    @pytest.mark.asyncio
    @pytest.mark.skipif(
        not os.environ.get("GITHUB_TOKEN"),
        reason="需要 GITHUB_TOKEN",
    )
    async def test_search_github(self) -> None:
        """测试 GitHub 搜索（需要网络）."""
        async with RemoteSearch() as search:
            results = await search.search(
                pattern="def main",
                repo="git-fixtures/basic",
                platform="github",
                max_results=5,
            )

            assert isinstance(results, list)

    @pytest.mark.asyncio
    async def test_get_statistics(self, remote_search: RemoteSearch) -> None:
        """测试获取统计信息."""
        stats = remote_search.get_statistics()
        assert isinstance(stats, SearchStatistics)

    @pytest.mark.asyncio
    async def test_clear_cache(self) -> None:
        """测试清空缓存."""
        search = RemoteSearch(use_cache=True)
        await search.initialize()

        try:
            # 应先设置一些缓存
            await search._cache.set("test", "value")  # type: ignore

            # 清空
            await search.clear_cache()

            # 验证已清空
            result = await search._cache.get("test")  # type: ignore
            assert result is None
        finally:
            await search.close()

    @pytest.mark.asyncio
    @pytest.mark.skipif(
        not os.environ.get("GITHUB_TOKEN"),
        reason="需要 GITHUB_TOKEN",
    )
    async def test_search_multiple_repos(self) -> None:
        """测试多仓库搜索（需要网络）."""
        async with RemoteSearch() as search:
            results = await search.search_multiple(
                pattern="README",
                repos=["git-fixtures/basic", "git-fixtures/small"],
                max_results_per_repo=3,
            )

            assert isinstance(results, dict)
            assert "git-fixtures/basic" in results
            assert "git-fixtures/small" in results


class TestLocalSearchIntegration:
    """本地搜索集成测试."""

    @pytest.mark.asyncio
    async def test_full_search_workflow(self, tmp_path: Path) -> None:
        """测试完整搜索工作流."""
        # 创建测试项目结构
        project = tmp_path / "my_project"
        project.mkdir()

        src = project / "src"
        src.mkdir()
        (src / "main.py").write_text("""
def main():
    print("Hello")

if __name__ == "__main__":
    main()
""")

        tests = project / "tests"
        tests.mkdir()
        (tests / "test_main.py").write_text("""
def test_main():
    assert True
""")

        # 执行搜索
        async with LocalSearch() as search:
            # 搜索函数定义
            func_results = await search.search(
                pattern=r"^def \w+",
                path=str(project),
                include=["*.py"],
                use_regex=True,
            )

            assert len(func_results) >= 2

            # 搜索特定内容
            main_results = await search.search(
                pattern="def main",
                path=str(project),
                include=["*.py"],
            )

            assert len(main_results) >= 1
            assert any("main.py" in r.file_path for r in main_results)
