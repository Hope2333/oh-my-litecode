"""
Remote 模块 - 远程仓库搜索功能.

本模块提供远程代码仓库的搜索能力，支持：
- GitHub CLI (gh) 集成
- Web 爬虫搜索
- Git 命令通路
- 智能通路管理（PathwayManager）

Example:
    ```python
    from grep_app_enhanced.remote import (
        GitHubCLI,
        GitCrawler,
        GitClient,
        PathwayManager,
        PathwayType,
        PlatformType,
    )

    # 使用 GitHub CLI
    gh = GitHubCLI()
    results = await gh.search_repos("python")

    # 使用爬虫
    crawler = GitCrawler()
    code = await crawler.fetch_file("https://github.com/...", "main")

    # 使用通路管理器（推荐）
    manager = PathwayManager(token="ghp_xxx")
    await manager.initialize()
    response = await manager.search("TODO", repo="owner/repo")
    ```

Supported Platforms:
    - GitHub (完整支持)
    - GitLab (通过 API 和 Git 命令)
    - Gitee (通过 API 和 Git 命令)
    - 其他 Git 仓库

Pathway Types:
    - gh_cli: GitHub CLI（最快，需要安装和认证）
    - api: REST API（需要 Token）
    - crawler: HTTP 爬虫（无需认证）
    - git_clone: Git 克隆后本地搜索（最完整）

Author:
    Oh My LiteCode Team
"""

from __future__ import annotations

from .crawler import GitCrawler, RepositorySearchResult, RobotsParser, RateLimiter
from .gh_cli import GitHubCLI, GitHubRepo, CodeSearchResult
from .git_client import GitClient, GitCommit, GitFile, GitBlame
from .pathway_manager import (
    PathwayManager,
    PathwayType,
    PlatformType,
    PathwayStatus,
    SearchRequest,
    SearchResponse,
    PerformanceStats,
    Checkpoint,
)

__all__ = [
    # 核心客户端
    "GitHubCLI",
    "GitCrawler",
    "GitClient",
    "PathwayManager",
    # 枚举类型
    "PathwayType",
    "PlatformType",
    # 数据类
    "PathwayStatus",
    "SearchRequest",
    "SearchResponse",
    "PerformanceStats",
    "Checkpoint",
    "GitHubRepo",
    "CodeSearchResult",
    "RepositorySearchResult",
    "GitCommit",
    "GitFile",
    "GitBlame",
    # 工具类
    "RobotsParser",
    "RateLimiter",
]
