"""
Remote 模块测试.

测试 GitHubCLI, GitCrawler, 和 GitClient 的功能.

Usage:
    pytest tests/test_remote.py -v

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

from grep_app_enhanced.remote import GitHubCLI, GitClient, GitCrawler
from grep_app_enhanced.remote.gh_cli import CodeSearchResult, GitHubRepo


class TestGitHubRepo:
    """测试 GitHubRepo 数据类."""

    def test_from_dict(self) -> None:
        """测试从字典创建实例."""
        data = {
            "full_name": "owner/repo",
            "description": "A test repository",
            "html_url": "https://github.com/owner/repo",
            "clone_url": "https://github.com/owner/repo.git",
            "stargazers_count": 100,
            "forks_count": 50,
            "language": "Python",
            "updated_at": "2024-01-01T00:00:00Z",
            "topics": ["test", "python"],
        }

        repo = GitHubRepo.from_dict(data)

        assert repo.full_name == "owner/repo"
        assert repo.description == "A test repository"
        assert repo.stargazers_count == 100
        assert repo.language == "Python"
        assert "test" in repo.topics


class TestCodeSearchResult:
    """测试 CodeSearchResult 数据类."""

    def test_from_dict(self) -> None:
        """测试从字典创建实例."""
        data = {
            "name": "main.py",
            "path": "src/main.py",
            "repository": {
                "full_name": "owner/repo",
            },
            "html_url": "https://github.com/owner/repo/blob/main/src/main.py",
            "text_matches": [
                {
                    "line_number": 10,
                    "fragment": "def main():",
                }
            ],
        }

        result = CodeSearchResult.from_dict(data)

        assert result.name == "main.py"
        assert result.path == "src/main.py"
        assert result.repository == "owner/repo"
        assert len(result.matches) == 1


class TestGitHubCLI:
    """测试 GitHubCLI 类."""

    @pytest.fixture
    def gh(self) -> GitHubCLI:
        """创建 GitHubCLI 实例."""
        return GitHubCLI(timeout=10)

    def test_initialization(self, gh: GitHubCLI) -> None:
        """测试初始化."""
        assert gh.timeout == 10
        assert gh.api_base == GitHubCLI.API_BASE

    def test_custom_api_base(self) -> None:
        """测试自定义 API 基础 URL."""
        gh = GitHubCLI(api_base="https://api.github.enterprise.com")
        assert gh.api_base == "https://api.github.enterprise.com"

    @pytest.mark.asyncio
    async def test_context_manager(self) -> None:
        """测试异步上下文管理器."""
        async with GitHubCLI() as gh:
            assert gh._client is not None

        # 退出后客户端应关闭
        assert gh._client is None

    @pytest.mark.asyncio
    async def test_check_gh_available(self, gh: GitHubCLI) -> None:
        """测试 gh CLI 可用性检查."""
        # 这个测试取决于系统是否安装了 gh
        result = gh._check_gh_available()
        assert isinstance(result, bool)

    def test_get_headers_without_token(self, gh: GitHubCLI) -> None:
        """测试无 Token 时的请求头."""
        headers = gh._get_headers()

        assert "Accept" in headers
        assert "User-Agent" in headers
        # 无 Token 时不应有 Authorization
        assert "Authorization" not in headers

    def test_get_headers_with_token(self) -> None:
        """测试有 Token 时的请求头."""
        gh = GitHubCLI(token="test_token")
        headers = gh._get_headers()

        assert headers.get("Authorization") == "Bearer test_token"

    @pytest.mark.asyncio
    @pytest.mark.skipif(
        not os.environ.get("GITHUB_TOKEN"),
        reason="需要 GITHUB_TOKEN",
    )
    async def test_search_repos(self) -> None:
        """测试搜索仓库（需要网络）."""
        async with GitHubCLI() as gh:
            repos = await gh.search_repos("python", language="Python", per_page=3)

            assert len(repos) <= 3
            if repos:
                assert isinstance(repos[0], GitHubRepo)

    @pytest.mark.asyncio
    @pytest.mark.skipif(
        not os.environ.get("GITHUB_TOKEN"),
        reason="需要 GITHUB_TOKEN",
    )
    async def test_get_user_info(self) -> None:
        """测试获取用户信息（需要网络）."""
        async with GitHubCLI() as gh:
            user = await gh.get_user_info()

            assert "login" in user


class TestGitCrawler:
    """测试 GitCrawler 类."""

    @pytest.fixture
    def crawler(self) -> GitCrawler:
        """创建 GitCrawler 实例."""
        return GitCrawler(timeout=10)

    def test_initialization(self, crawler: GitCrawler) -> None:
        """测试初始化."""
        assert crawler.timeout == 10
        assert crawler.max_retries == 3

    def test_parse_github_url(self, crawler: GitCrawler) -> None:
        """测试解析 GitHub URL."""
        info = crawler.parse_repo_url("https://github.com/owner/repo")

        assert info.owner == "owner"
        assert info.repo == "repo"
        assert info.platform == "github"

    def test_parse_gitlab_url(self, crawler: GitCrawler) -> None:
        """测试解析 GitLab URL."""
        info = crawler.parse_repo_url("https://gitlab.com/owner/repo")

        assert info.owner == "owner"
        assert info.repo == "repo"
        assert info.platform == "gitlab"

    def test_parse_gitee_url(self, crawler: GitCrawler) -> None:
        """测试解析 Gitee URL."""
        info = crawler.parse_repo_url("https://gitee.com/owner/repo")

        assert info.owner == "owner"
        assert info.repo == "repo"
        assert info.platform == "gitee"

    def test_parse_url_with_git_suffix(self, crawler: GitCrawler) -> None:
        """测试解析带 .git 后缀的 URL."""
        info = crawler.parse_repo_url("https://github.com/owner/repo.git")

        assert info.owner == "owner"
        assert info.repo == "repo"

    def test_parse_url_with_ssh(self, crawler: GitCrawler) -> None:
        """测试解析 SSH URL."""
        info = crawler.parse_repo_url("git@github.com:owner/repo.git")

        assert info.owner == "owner"
        assert info.repo == "repo"

    def test_parse_invalid_url(self, crawler: GitCrawler) -> None:
        """测试解析无效 URL."""
        with pytest.raises(ValueError):
            crawler.parse_repo_url("https://invalid.com/owner/repo")

    def test_build_raw_url_github(self, crawler: GitCrawler) -> None:
        """测试构建 GitHub 原始 URL."""
        info = crawler.parse_repo_url("https://github.com/owner/repo")
        url = info.build_raw_url("main", "src/file.py")

        assert url == "https://raw.githubusercontent.com/owner/repo/main/src/file.py"

    def test_build_raw_url_gitlab(self, crawler: GitCrawler) -> None:
        """测试构建 GitLab 原始 URL."""
        info = crawler.parse_repo_url("https://gitlab.com/owner/repo")
        url = info.build_raw_url("main", "src/file.py")

        assert url == "https://gitlab.com/owner/repo/-/raw/main/src/file.py"

    @pytest.mark.asyncio
    async def test_context_manager(self, crawler: GitCrawler) -> None:
        """测试异步上下文管理器."""
        async with crawler:
            assert crawler._client is not None

        assert crawler._client is None

    @pytest.mark.asyncio
    @pytest.mark.skip(reason="需要网络连接")
    async def test_fetch_file(self) -> None:
        """测试获取文件（需要网络）."""
        async with GitCrawler() as crawler:
            content = await crawler.fetch_file(
                "https://github.com/git/git",
                "master",
                "README"
            )
            assert len(content) > 0


class TestGitClient:
    """测试 GitClient 类."""

    @pytest.fixture
    def git(self) -> GitClient:
        """创建 GitClient 实例."""
        return GitClient(timeout=30)

    def test_initialization(self, git: GitClient) -> None:
        """测试初始化."""
        assert git.git_path is not None
        assert git.timeout == 30

    def test_git_not_found(self) -> None:
        """测试 git 未安装的情况."""
        # 保存原始 PATH
        import shutil

        original_which = shutil.which

        def mock_which(cmd: str) -> None:
            return None

        shutil.which = mock_which  # type: ignore

        try:
            with pytest.raises(FileNotFoundError):
                GitClient()
        finally:
            shutil.which = original_which

    @pytest.mark.asyncio
    async def test_run_command(self, git: GitClient) -> None:
        """测试运行命令."""
        returncode, stdout, stderr = await git._run_command(["--version"])

        assert returncode == 0
        assert "git version" in stdout

    @pytest.mark.asyncio
    async def test_is_git_repo(self, git: GitClient, tmp_path: Path) -> None:
        """测试检查是否为 Git 仓库."""
        # 非仓库目录
        assert not await git.is_git_repo(tmp_path)

        # 创建仓库
        await git._run_command(["init"], cwd=tmp_path)
        assert await git.is_git_repo(tmp_path)

    @pytest.mark.asyncio
    async def test_clone(self, git: GitClient, tmp_path: Path) -> None:
        """测试克隆仓库."""
        dest = tmp_path / "test_repo"

        # 克隆一个小型公开仓库
        await git.clone(
            "https://github.com/git-fixtures/basic.git",
            dest,
            depth=1,
        )

        assert dest.exists()
        assert (dest / ".git").exists()

    @pytest.mark.asyncio
    async def test_log(self, git: GitClient, tmp_path: Path) -> None:
        """测试查看提交历史."""
        dest = tmp_path / "test_repo"

        # 先克隆
        await git.clone(
            "https://github.com/git-fixtures/basic.git",
            dest,
            depth=5,
        )

        # 获取日志
        commits = await git.log(dest, max_count=3)

        assert len(commits) <= 3
        if commits:
            assert commits[0].sha is not None
            assert commits[0].message != ""

    @pytest.mark.asyncio
    async def test_ls_files(self, git: GitClient, tmp_path: Path) -> None:
        """测试列出文件."""
        dest = tmp_path / "test_repo"

        await git.clone(
            "https://github.com/git-fixtures/basic.git",
            dest,
            depth=1,
        )

        files = await git.ls_files(dest)

        assert len(files) > 0
        assert any(f.path.endswith(".go") for f in files)

    @pytest.mark.asyncio
    async def test_grep(self, git: GitClient, tmp_path: Path) -> None:
        """测试在仓库中搜索."""
        dest = tmp_path / "test_repo"

        await git.clone(
            "https://github.com/git-fixtures/basic.git",
            dest,
            depth=1,
        )

        results = await git.grep(dest, "package", path=".")

        assert len(results) > 0
        assert any("package" in r.get("content", "").lower() for r in results)

    @pytest.mark.asyncio
    async def test_get_current_branch(self, git: GitClient, tmp_path: Path) -> None:
        """测试获取当前分支."""
        dest = tmp_path / "test_repo"

        await git.clone(
            "https://github.com/git-fixtures/basic.git",
            dest,
            depth=1,
        )

        branch = await git.get_current_branch(dest)
        assert branch is not None

    @pytest.mark.asyncio
    async def test_get_remote_url(self, git: GitClient, tmp_path: Path) -> None:
        """测试获取远程 URL."""
        dest = tmp_path / "test_repo"

        await git.clone(
            "https://github.com/git-fixtures/basic.git",
            dest,
            depth=1,
        )

        url = await git.get_remote_url(dest)
        assert url is not None
        assert "git-fixtures/basic" in url


class TestRemoteIntegration:
    """集成测试."""

    @pytest.mark.asyncio
    @pytest.mark.skipif(
        not os.environ.get("GITHUB_TOKEN"),
        reason="需要 GITHUB_TOKEN",
    )
    async def test_github_search_workflow(self) -> None:
        """测试 GitHub 搜索工作流."""
        async with GitHubCLI() as gh:
            # 搜索仓库
            repos = await gh.search_repos("python", language="Python", per_page=1)

            if repos:
                repo = repos[0]
                # 搜索代码
                results = await gh.search_code(
                    "def main",
                    owner=repo.full_name.split("/")[0],
                    repo=repo.full_name.split("/")[1],
                    per_page=3,
                )

                assert isinstance(results, list)
