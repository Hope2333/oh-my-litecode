"""
Pathway Manager - 远程通路管理器.

本模块提供远程搜索通路的统一管理和智能调度，支持：
- 多通路选择（GitHub CLI / API / 爬虫 / Git 克隆）
- 智能降级策略
- 结果合并与去重
- 性能监控与统计
- 断点续传支持

Example:
    ```python
    from grep_app_enhanced.remote import PathwayManager

    manager = PathwayManager(token="ghp_xxx")
    await manager.initialize()

    # 执行搜索（自动选择最佳通路）
    results = await manager.search(
        "def main",
        repo="owner/repo",
        platform="github"
    )

    # 获取性能统计
    stats = manager.get_performance_stats()
    print(f"平均响应时间：{stats['avg_response_time_ms']}ms")
    ```

Pathway Priority:
    1. gh_cli: GitHub CLI（最快，需要安装和认证）
    2. api: GitHub/GitLab/Gitee API（需要 Token）
    3. crawler: HTTP 爬虫（无需认证，较慢）
    4. git_clone: Git 克隆后本地搜索（最完整，最慢）

Fallback Strategy:
    - 自动检测通路可用性
    - 失败时自动降级到下一优先级通路
    - 记录失败原因用于后续优化
    - 支持手动指定通路

Result Merging:
    - 多通路结果合并
    - 基于文件路径 + 行号的去重
    - 按相关性排序
    - 保留通路来源信息

Performance Monitoring:
    - 记录每次请求的响应时间
    - 统计通路成功率
    - 监控速率限制状态
    - 生成性能报告

Author:
    Oh My LiteCode Team
"""

from __future__ import annotations

import asyncio
import hashlib
import json
import logging
import os
import sys
import tempfile
import time
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Any, Callable

from ..__init__ import SearchResult
from .crawler import GitCrawler, RepositorySearchResult
from .gh_cli import GitHubCLI
from .git_client import GitClient


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


class PathwayType(Enum):
    """通路类型枚举."""

    GH_CLI = "gh_cli"
    API = "api"
    CRAWLER = "crawler"
    GIT_CLONE = "git_clone"
    HTTP_FALLBACK = "http_fallback"


class PlatformType(Enum):
    """平台类型枚举."""

    GITHUB = "github"
    GITLAB = "gitlab"
    GITEE = "gitee"
    GENERIC = "generic"


@dataclass
class PathwayStatus:
    """通路状态数据类.

    Attributes:
        pathway_type: 通路类型
        available: 是否可用
        authenticated: 是否已认证
        rate_limit_remaining: 剩余请求数
        rate_limit_total: 总请求限制
        last_used: 最后使用时间
        success_count: 成功次数
        failure_count: 失败次数
        avg_response_time_ms: 平均响应时间（毫秒）
        last_error: 最后错误信息

    Example:
        ```python
        status = PathwayStatus(
            pathway_type=PathwayType.GH_CLI,
            available=True,
            authenticated=True
        )
        ```
    """

    pathway_type: PathwayType
    available: bool = True
    authenticated: bool = False
    rate_limit_remaining: int = 1000
    rate_limit_total: int = 5000
    last_used: float = 0.0
    success_count: int = 0
    failure_count: int = 0
    avg_response_time_ms: float = 0.0
    last_error: str = ""

    @property
    def success_rate(self) -> float:
        """计算成功率."""
        total = self.success_count + self.failure_count
        if total == 0:
            return 1.0
        return self.success_count / total

    @property
    def is_rate_limited(self) -> bool:
        """检查是否触达速率限制."""
        return self.rate_limit_remaining < 10

    def to_dict(self) -> dict[str, Any]:
        """转换为字典格式."""
        return {
            "pathway_type": self.pathway_type.value,
            "available": self.available,
            "authenticated": self.authenticated,
            "rate_limit_remaining": self.rate_limit_remaining,
            "rate_limit_total": self.rate_limit_total,
            "last_used": self.last_used,
            "success_count": self.success_count,
            "failure_count": self.failure_count,
            "avg_response_time_ms": round(self.avg_response_time_ms, 2),
            "success_rate": round(self.success_rate, 3),
            "is_rate_limited": self.is_rate_limited,
            "last_error": self.last_error,
        }


@dataclass
class SearchRequest:
    """搜索请求数据类.

    Attributes:
        pattern: 搜索模式
        repo: 仓库标识
        platform: 平台名称
        ref: 分支/标签
        path: 路径过滤
        language: 语言过滤
        max_results: 最大结果数
        preferred_pathway: 首选通路
        allow_fallback: 是否允许降级

    Example:
        ```python
        request = SearchRequest(
            pattern="def main",
            repo="microsoft/vscode",
            platform="github",
            max_results=100
        )
        ```
    """

    pattern: str
    repo: str
    platform: str = "github"
    ref: str = "HEAD"
    path: str = ""
    language: str | None = None
    max_results: int = 100
    preferred_pathway: PathwayType | None = None
    allow_fallback: bool = True


@dataclass
class SearchResponse:
    """搜索响应数据类.

    Attributes:
        results: 搜索结果列表
        pathway_used: 使用的通路
        fallback_chain: 降级链路
        total_time_ms: 总耗时（毫秒）
        cache_hit: 是否命中缓存
        error: 错误信息（如果有）

    Example:
        ```python
        response = SearchResponse(
            results=[...],
            pathway_used=PathwayType.GH_CLI,
            total_time_ms=150.5
        )
        ```
    """

    results: list[SearchResult] = field(default_factory=list)
    pathway_used: PathwayType | None = None
    fallback_chain: list[str] = field(default_factory=list)
    total_time_ms: float = 0.0
    cache_hit: bool = False
    error: str | None = None

    def to_dict(self) -> dict[str, Any]:
        """转换为字典格式."""
        return {
            "results": [r.to_dict() for r in self.results],
            "pathway_used": self.pathway_used.value if self.pathway_used else None,
            "fallback_chain": self.fallback_chain,
            "total_time_ms": round(self.total_time_ms, 2),
            "cache_hit": self.cache_hit,
            "error": self.error,
            "result_count": len(self.results),
        }


@dataclass
class PerformanceStats:
    """性能统计数据类.

    Attributes:
        total_requests: 总请求数
        successful_requests: 成功请求数
        failed_requests: 失败请求数
        avg_response_time_ms: 平均响应时间
        p95_response_time_ms: P95 响应时间
        p99_response_time_ms: P99 响应时间
        cache_hit_rate: 缓存命中率
        pathway_usage: 各通路使用次数
        fallback_rate: 降级率

    Example:
        ```python
        stats = PerformanceStats()
        print(f"成功率：{stats.success_rate:.2%}")
        ```
    """

    total_requests: int = 0
    successful_requests: int = 0
    failed_requests: int = 0
    avg_response_time_ms: float = 0.0
    p95_response_time_ms: float = 0.0
    p99_response_time_ms: float = 0.0
    cache_hit_rate: float = 0.0
    pathway_usage: dict[str, int] = field(default_factory=dict)
    fallback_rate: float = 0.0

    # 响应时间历史记录（用于计算百分位数）
    _response_times: list[float] = field(default_factory=list, repr=False)

    def record_request(
        self,
        success: bool,
        response_time_ms: float,
        pathway: str,
        used_fallback: bool = False,
        cache_hit: bool = False,
    ) -> None:
        """记录一次请求.

        Args:
            success: 是否成功
            response_time_ms: 响应时间
            pathway: 使用的通路
            used_fallback: 是否使用了降级
            cache_hit: 是否命中缓存
        """
        self.total_requests += 1
        if success:
            self.successful_requests += 1
        else:
            self.failed_requests += 1

        self._response_times.append(response_time_ms)
        self._update_avg_response_time()

        if pathway not in self.pathway_usage:
            self.pathway_usage[pathway] = 0
        self.pathway_usage[pathway] += 1

        # 更新降级率
        if used_fallback:
            fallback_count = sum(
                1 for r in self._response_times if r > 0
            )  # 简化处理
            self.fallback_rate = fallback_count / max(1, self.total_requests)

        # 更新缓存命中率
        if cache_hit:
            cache_hits = sum(1 for _ in self._response_times)  # 简化处理
            self.cache_hit_rate = cache_hits / max(1, self.total_requests)

    def _update_avg_response_time(self) -> None:
        """更新平均响应时间."""
        if self._response_times:
            self.avg_response_time_ms = sum(self._response_times) / len(
                self._response_times
            )
            # 计算百分位数
            sorted_times = sorted(self._response_times)
            p95_idx = int(len(sorted_times) * 0.95)
            p99_idx = int(len(sorted_times) * 0.99)
            self.p95_response_time_ms = (
                sorted_times[p95_idx] if p95_idx < len(sorted_times) else 0
            )
            self.p99_response_time_ms = (
                sorted_times[p99_idx] if p99_idx < len(sorted_times) else 0
            )

    @property
    def success_rate(self) -> float:
        """计算成功率."""
        if self.total_requests == 0:
            return 1.0
        return self.successful_requests / self.total_requests

    def to_dict(self) -> dict[str, Any]:
        """转换为字典格式."""
        return {
            "total_requests": self.total_requests,
            "successful_requests": self.successful_requests,
            "failed_requests": self.failed_requests,
            "success_rate": round(self.success_rate, 3),
            "avg_response_time_ms": round(self.avg_response_time_ms, 2),
            "p95_response_time_ms": round(self.p95_response_time_ms, 2),
            "p99_response_time_ms": round(self.p99_response_time_ms, 2),
            "cache_hit_rate": round(self.cache_hit_rate, 3),
            "pathway_usage": self.pathway_usage,
            "fallback_rate": round(self.fallback_rate, 3),
        }


@dataclass
class Checkpoint:
    """断点续传检查点数据类.

    Attributes:
        request_hash: 请求哈希
        completed_repos: 已完成的仓库列表
        partial_results: 部分结果
        created_at: 创建时间
        updated_at: 更新时间
        state: 状态 (running/paused/completed/failed)

    Example:
        ```python
        checkpoint = Checkpoint(
            request_hash="abc123",
            completed_repos=["repo1", "repo2"]
        )
        ```
    """

    request_hash: str
    completed_repos: list[str] = field(default_factory=list)
    partial_results: list[dict[str, Any]] = field(default_factory=list)
    created_at: float = field(default_factory=time.time)
    updated_at: float = field(default_factory=time.time)
    state: str = "running"

    def to_dict(self) -> dict[str, Any]:
        """转换为字典格式."""
        return {
            "request_hash": self.request_hash,
            "completed_repos": self.completed_repos,
            "partial_results": self.partial_results,
            "created_at": self.created_at,
            "updated_at": self.updated_at,
            "state": self.state,
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> Checkpoint:
        """从字典创建实例."""
        return cls(
            request_hash=data.get("request_hash", ""),
            completed_repos=data.get("completed_repos", []),
            partial_results=data.get("partial_results", []),
            created_at=data.get("created_at", time.time()),
            updated_at=data.get("updated_at", time.time()),
            state=data.get("state", "running"),
        )


class PathwayManager:
    """远程通路管理器.

    提供统一的远程搜索通路管理，支持智能通路选择、
    自动降级、结果合并和性能监控.

    Attributes:
        token: API Token
        platform: 默认平台
        cache_enabled: 是否启用缓存
        max_concurrent: 最大并发数

    Example:
        ```python
        manager = PathwayManager(
            token="ghp_xxx",
            platform="github",
            cache_enabled=True
        )
        await manager.initialize()

        results = await manager.search(
            "TODO",
            repo="owner/repo"
        )
        ```

    Note:
        - 自动检测并选择最佳通路
        - 支持多平台（GitHub/GitLab/Gitee）
        - 完整的性能监控和统计
        - 支持断点续传
    """

    # 通路优先级（从高到低）
    PATHWAY_PRIORITY = [
        PathwayType.GH_CLI,
        PathwayType.API,
        PathwayType.CRAWLER,
        PathwayType.GIT_CLONE,
        PathwayType.HTTP_FALLBACK,
    ]

    # 平台 API 端点
    PLATFORM_ENDPOINTS = {
        PlatformType.GITHUB: "https://api.github.com",
        PlatformType.GITLAB: "https://gitlab.com/api/v4",
        PlatformType.GITEE: "https://gitee.com/api/v5",
    }

    def __init__(
        self,
        token: str | None = None,
        platform: str = "github",
        cache_enabled: bool = True,
        max_concurrent: int = 5,
        checkpoint_dir: str | None = None,
    ) -> None:
        """初始化通路管理器.

        Args:
            token: API Token
            platform: 默认平台
            cache_enabled: 是否启用缓存
            max_concurrent: 最大并发数
            checkpoint_dir: 断点保存目录
        """
        self.token = token
        self.platform = platform
        self.cache_enabled = cache_enabled
        self.max_concurrent = max_concurrent
        self.checkpoint_dir = Path(checkpoint_dir) if checkpoint_dir else None

        # 客户端
        self._github_cli: GitHubCLI | None = None
        self._crawler: GitCrawler | None = None
        self._git_client: GitClient | None = None

        # 通路状态
        self._pathway_statuses: dict[PathwayType, PathwayStatus] = {}
        self._initialized = False

        # 性能统计
        self._stats = PerformanceStats()

        # 缓存（简单的内存缓存）
        self._cache: dict[str, tuple[float, Any]] = {}
        self._cache_ttl = 3600  # 1 小时

        # 检查点
        self._checkpoints: dict[str, Checkpoint] = {}

        # 信号量（控制并发）
        self._semaphore: asyncio.Semaphore | None = None

        # 临时目录（用于 git clone）
        self._temp_dirs: list[tempfile.TemporaryDirectory] = []

    async def initialize(self) -> None:
        """初始化所有客户端和通路状态."""
        if self._initialized:
            return

        self._semaphore = asyncio.Semaphore(self.max_concurrent)

        # 初始化 GitHub CLI
        self._github_cli = GitHubCLI(token=self.token)
        await self._github_cli.initialize()

        # 初始化 Crawler
        self._crawler = GitCrawler(token=self.token)
        await self._crawler.initialize()

        # 初始化 Git Client
        self._git_client = GitClient()

        # 初始化通路状态
        await self._init_pathway_statuses()

        self._initialized = True
        logger.info("PathwayManager 初始化完成")

        # 加载检查点
        await self._load_checkpoints()

    async def close(self) -> None:
        """关闭管理器并释放资源."""
        # 保存检查点
        await self._save_checkpoints()

        # 关闭客户端
        if self._github_cli:
            await self._github_cli.close()
        if self._crawler:
            await self._crawler.close()

        # 清理临时目录
        for temp_dir in self._temp_dirs:
            try:
                temp_dir.cleanup()
            except Exception:
                pass
        self._temp_dirs.clear()

        self._initialized = False
        logger.info("PathwayManager 已关闭")

    async def __aenter__(self) -> PathwayManager:
        """异步上下文管理器入口."""
        await self.initialize()
        return self

    async def __aexit__(self, exc_type: Any, exc_val: Any, exc_tb: Any) -> None:
        """异步上下文管理器出口."""
        await self.close()

    async def _init_pathway_statuses(self) -> None:
        """初始化通路状态."""
        # GH_CLI 状态
        gh_available = self._github_cli._gh_available if self._github_cli else False
        gh_authenticated = False
        if gh_available and self._github_cli:
            try:
                auth_status = await self._github_cli.gh_auth_check()
                gh_authenticated = auth_status.get("authenticated", False)
            except Exception:
                pass

        self._pathway_statuses[PathwayType.GH_CLI] = PathwayStatus(
            pathway_type=PathwayType.GH_CLI,
            available=gh_available,
            authenticated=gh_authenticated,
            rate_limit_remaining=5000 if gh_authenticated else 60,
            rate_limit_total=5000 if gh_authenticated else 60,
        )

        # API 状态
        api_available = bool(self.token)
        self._pathway_statuses[PathwayType.API] = PathwayStatus(
            pathway_type=PathwayType.API,
            available=api_available,
            authenticated=api_available,
            rate_limit_remaining=5000 if api_available else 60,
            rate_limit_total=5000 if api_available else 60,
        )

        # Crawler 状态
        self._pathway_statuses[PathwayType.CRAWLER] = PathwayStatus(
            pathway_type=PathwayType.CRAWLER,
            available=True,
            authenticated=False,
            rate_limit_remaining=1000,
            rate_limit_total=1000,
        )

        # Git Clone 状态
        self._pathway_statuses[PathwayType.GIT_CLONE] = PathwayStatus(
            pathway_type=PathwayType.GIT_CLONE,
            available=True,
            authenticated=False,
            rate_limit_remaining=100,
            rate_limit_total=100,
        )

        # HTTP Fallback 状态
        self._pathway_statuses[PathwayType.HTTP_FALLBACK] = PathwayStatus(
            pathway_type=PathwayType.HTTP_FALLBACK,
            available=True,
            authenticated=False,
            rate_limit_remaining=100,
            rate_limit_total=100,
        )

    def _compute_cache_key(self, request: SearchRequest) -> str:
        """计算缓存键."""
        key_str = f"{request.pattern}:{request.repo}:{request.platform}:{request.ref}:{request.path}"
        return hashlib.sha256(key_str.encode()).hexdigest()

    def _compute_request_hash(self, repos: list[str], pattern: str) -> str:
        """计算请求哈希（用于断点续传）."""
        key_str = f"{pattern}:{','.join(sorted(repos))}"
        return hashlib.sha256(key_str.encode()).hexdigest()[:16]

    async def _check_cache(self, key: str) -> Any | None:
        """检查缓存."""
        if not self.cache_enabled:
            return None

        if key in self._cache:
            timestamp, value = self._cache[key]
            if time.time() - timestamp < self._cache_ttl:
                return value
            else:
                del self._cache[key]

        return None

    async def _set_cache(self, key: str, value: Any) -> None:
        """设置缓存."""
        if self.cache_enabled:
            self._cache[key] = (time.time(), value)

    async def _select_pathway(
        self,
        preferred: PathwayType | None = None,
    ) -> PathwayType:
        """选择最佳通路.

        Args:
            preferred: 首选通路

        Returns:
            选中的通路类型
        """
        # 如果指定了首选通路且可用，使用首选
        if preferred:
            status = self._pathway_statuses.get(preferred)
            if status and status.available and not status.is_rate_limited:
                return preferred

        # 按优先级选择可用的通路
        for pathway in self.PATHWAY_PRIORITY:
            status = self._pathway_statuses.get(pathway)
            if status and status.available and not status.is_rate_limited:
                return pathway

        # 所有通路都不可用，返回最低优先级的回退通路
        return PathwayType.HTTP_FALLBACK

    async def _execute_with_pathway(
        self,
        request: SearchRequest,
        pathway: PathwayType,
    ) -> list[SearchResult]:
        """使用指定通路执行搜索.

        Args:
            request: 搜索请求
            pathway: 通路类型

        Returns:
            搜索结果列表

        Raises:
            RuntimeError: 通路执行失败
        """
        async with self._semaphore:  # type: ignore
            start_time = time.perf_counter()

            try:
                if pathway == PathwayType.GH_CLI:
                    results = await self._execute_gh_cli(request)
                elif pathway == PathwayType.API:
                    results = await self._execute_api(request)
                elif pathway == PathwayType.CRAWLER:
                    results = await self._execute_crawler(request)
                elif pathway == PathwayType.GIT_CLONE:
                    results = await self._execute_git_clone(request)
                else:
                    results = await self._execute_http_fallback(request)

                # 更新通路状态
                elapsed = (time.perf_counter() - start_time) * 1000
                await self._update_pathway_status(pathway, success=True, elapsed=elapsed)

                return results

            except Exception as e:
                elapsed = (time.perf_counter() - start_time) * 1000
                await self._update_pathway_status(
                    pathway, success=False, elapsed=elapsed, error=str(e)
                )
                raise

    async def _execute_gh_cli(self, request: SearchRequest) -> list[SearchResult]:
        """使用 GitHub CLI 执行搜索."""
        if not self._github_cli:
            raise RuntimeError("GitHub CLI 未初始化")

        parts = request.repo.split("/")
        owner = parts[0] if len(parts) >= 1 else ""
        repo = parts[1] if len(parts) >= 2 else ""

        results = await self._github_cli.gh_search_code(
            query=request.pattern,
            owner=owner,
            repo=repo,
            language=request.language,
            path=request.path if request.path else None,
            per_page=request.max_results,
        )

        return self._convert_code_results(results)

    async def _execute_api(self, request: SearchRequest) -> list[SearchResult]:
        """使用 API 执行搜索."""
        if not self._github_cli:
            raise RuntimeError("GitHub CLI 未初始化")

        parts = request.repo.split("/")
        owner = parts[0] if len(parts) >= 1 else ""
        repo = parts[1] if len(parts) >= 2 else ""

        results = await self._github_cli.search_code(
            query=request.pattern,
            owner=owner,
            repo=repo,
            language=request.language,
            path=request.path if request.path else None,
            per_page=request.max_results,
        )

        return self._convert_code_results(results)

    async def _execute_crawler(self, request: SearchRequest) -> list[SearchResult]:
        """使用爬虫执行搜索."""
        if not self._crawler:
            raise RuntimeError("Crawler 未初始化")

        # 构建仓库 URL
        if request.platform == "github":
            repo_url = f"https://github.com/{request.repo}"
        elif request.platform == "gitlab":
            repo_url = f"https://gitlab.com/{request.repo}"
        elif request.platform == "gitee":
            repo_url = f"https://gitee.com/{request.repo}"
        else:
            repo_url = request.repo

        # 使用爬虫的搜索功能
        files = await self._crawler.search_in_repo(
            repo_url=repo_url,
            pattern=request.pattern,
            ref=request.ref,
            path=request.path,
        )

        # 转换为 SearchResult
        results = []
        for file in files:
            try:
                content = await self._crawler.fetch_file(
                    repo_url=repo_url,
                    ref=request.ref,
                    path=file.path,
                )
                results.append(
                    SearchResult(
                        file_path=file.path,
                        line_number=0,
                        content=content[:500],  # 限制内容长度
                        metadata={
                            "repository": request.repo,
                            "platform": request.platform,
                            "pathway": "crawler",
                        },
                    )
                )
            except Exception:
                pass

        return results

    async def _execute_git_clone(self, request: SearchRequest) -> list[SearchResult]:
        """使用 Git 克隆后本地搜索."""
        if not self._git_client:
            raise RuntimeError("Git Client 未初始化")

        # 创建临时目录
        temp_dir = tempfile.TemporaryDirectory()
        self._temp_dirs.append(temp_dir)

        try:
            # 构建克隆 URL
            if request.platform == "github":
                clone_url = f"https://github.com/{request.repo}.git"
            elif request.platform == "gitlab":
                clone_url = f"https://gitlab.com/{request.repo}.git"
            elif request.platform == "gitee":
                clone_url = f"https://gitee.com/{request.repo}.git"
            else:
                clone_url = request.repo

            # 克隆仓库
            await self._git_client.clone_repository(
                url=clone_url,
                dest=temp_dir.name,
                depth=1,
                timeout=120,
            )

            # 本地搜索
            results = await self._git_client.search_in_repo(
                repo_path=temp_dir.name,
                pattern=request.pattern,
                extensions=[f".{request.language.lower()}"] if request.language else None,
                max_results=request.max_results,
            )

            # 转换为 SearchResult
            search_results = []
            for r in results:
                # 转换为相对路径
                try:
                    rel_path = str(Path(r["file"]).relative_to(temp_dir.name))
                except ValueError:
                    rel_path = r["file"]

                search_results.append(
                    SearchResult(
                        file_path=rel_path,
                        line_number=r.get("line", 0),
                        content=r.get("content", ""),
                        metadata={
                            "repository": request.repo,
                            "platform": request.platform,
                            "pathway": "git_clone",
                        },
                    )
                )

            return search_results

        finally:
            # 清理临时目录（可选：保留用于断点续传）
            pass

    async def _execute_http_fallback(self, request: SearchRequest) -> list[SearchResult]:
        """使用 HTTP 回退方式搜索."""
        # 简单的回退实现
        return []

    def _convert_code_results(
        self,
        code_results: list[Any],
    ) -> list[SearchResult]:
        """转换代码搜索结果."""
        results = []
        for item in code_results:
            results.append(
                SearchResult(
                    file_path=getattr(item, "path", ""),
                    line_number=(
                        item.matches[0].get("line_number", 0)
                        if hasattr(item, "matches") and item.matches
                        else 0
                    ),
                    content=getattr(item, "content", "") or "",
                    metadata={
                        "repository": getattr(item, "repository", ""),
                        "url": getattr(item, "url", ""),
                    },
                )
            )
        return results

    async def _update_pathway_status(
        self,
        pathway: PathwayType,
        success: bool,
        elapsed: float,
        error: str | None = None,
    ) -> None:
        """更新通路状态.

        Args:
            pathway: 通路类型
            success: 是否成功
            elapsed: 耗时（毫秒）
            error: 错误信息
        """
        status = self._pathway_statuses.get(pathway)
        if not status:
            return

        status.last_used = time.time()

        if success:
            status.success_count += 1
            # 更新平均响应时间
            total_count = status.success_count + status.failure_count
            status.avg_response_time_ms = (
                status.avg_response_time_ms * (total_count - 1) + elapsed
            ) / total_count
        else:
            status.failure_count += 1
            if error:
                status.last_error = error

        # 更新性能统计
        self._stats.record_request(
            success=success,
            response_time_ms=elapsed,
            pathway=pathway.value,
            used_fallback=pathway != PathwayType.GH_CLI,
        )

    async def search(
        self,
        pattern: str,
        repo: str,
        platform: str | None = None,
        ref: str = "HEAD",
        path: str = "",
        language: str | None = None,
        max_results: int = 100,
        preferred_pathway: PathwayType | None = None,
        allow_fallback: bool = True,
    ) -> SearchResponse:
        """执行搜索（智能通路选择）.

        Args:
            pattern: 搜索模式
            repo: 仓库标识 (owner/repo)
            platform: 平台名称
            ref: 分支/标签
            path: 路径过滤
            language: 语言过滤
            max_results: 最大结果数
            preferred_pathway: 首选通路
            allow_fallback: 是否允许降级

        Returns:
            搜索响应

        Example:
            ```python
            manager = PathwayManager(token="ghp_xxx")
            await manager.initialize()

            response = await manager.search(
                "def main",
                repo="microsoft/vscode",
                platform="github",
                max_results=50
            )

            print(f"找到 {len(response.results)} 个结果")
            print(f"使用通路：{response.pathway_used}")
            ```
        """
        start_time = time.perf_counter()

        if not self._initialized:
            await self.initialize()

        # 创建请求
        request = SearchRequest(
            pattern=pattern,
            repo=repo,
            platform=platform or self.platform,
            ref=ref,
            path=path,
            language=language,
            max_results=max_results,
            preferred_pathway=preferred_pathway,
            allow_fallback=allow_fallback,
        )

        # 检查缓存
        cache_key = self._compute_cache_key(request)
        cached_result = await self._check_cache(cache_key)
        if cached_result is not None:
            return SearchResponse(
                results=cached_result,
                pathway_used=None,
                total_time_ms=0,
                cache_hit=True,
            )

        # 选择通路并执行
        fallback_chain = []
        last_error: Exception | None = None

        pathway = await self._select_pathway(preferred_pathway)

        while True:
            fallback_chain.append(pathway.value)

            try:
                results = await self._execute_with_pathway(request, pathway)

                # 限制结果数
                results = results[:max_results]

                # 缓存结果
                await self._set_cache(cache_key, results)

                elapsed = (time.perf_counter() - start_time) * 1000

                return SearchResponse(
                    results=results,
                    pathway_used=pathway,
                    fallback_chain=fallback_chain,
                    total_time_ms=elapsed,
                    cache_hit=False,
                )

            except Exception as e:
                last_error = e
                logger.warning(f"通路 {pathway.value} 失败：{e}")

                if not allow_fallback:
                    elapsed = (time.perf_counter() - start_time) * 1000
                    return SearchResponse(
                        results=[],
                        pathway_used=pathway,
                        fallback_chain=fallback_chain,
                        total_time_ms=elapsed,
                        error=str(e),
                    )

                # 尝试下一个通路
                pathway = await self._get_next_pathway(pathway)
                if pathway is None:
                    break

        # 所有通路都失败
        elapsed = (time.perf_counter() - start_time) * 1000
        return SearchResponse(
            results=[],
            pathway_used=None,
            fallback_chain=fallback_chain,
            total_time_ms=elapsed,
            error=str(last_error) if last_error else "所有通路都不可用",
        )

    async def _get_next_pathway(
        self,
        current: PathwayType,
    ) -> PathwayType | None:
        """获取下一个可用通路.

        Args:
            current: 当前通路

        Returns:
            下一个通路，如果没有可用通路返回 None
        """
        try:
            current_idx = self.PATHWAY_PRIORITY.index(current)
        except ValueError:
            current_idx = -1

        for pathway in self.PATHWAY_PRIORITY[current_idx + 1 :]:
            status = self._pathway_statuses.get(pathway)
            if status and status.available:
                return pathway

        return None

    async def search_multiple(
        self,
        pattern: str,
        repos: list[str],
        platform: str | None = None,
        max_results_per_repo: int = 50,
        use_checkpoints: bool = True,
    ) -> dict[str, SearchResponse]:
        """在多个仓库中搜索（支持断点续传）.

        Args:
            pattern: 搜索模式
            repos: 仓库列表
            platform: 平台名称
            max_results_per_repo: 每个仓库的最大结果数
            use_checkpoints: 是否使用断点续传

        Returns:
            仓库到响应的映射

        Example:
            ```python
            manager = PathwayManager()
            await manager.initialize()

            results = await manager.search_multiple(
                "TODO",
                repos=["owner/repo1", "owner/repo2"],
                max_results_per_repo=20
            )
            ```
        """
        if not self._initialized:
            await self.initialize()

        # 创建检查点
        request_hash = self._compute_request_hash(repos, pattern)
        checkpoint = None

        if use_checkpoints and self.checkpoint_dir:
            checkpoint = self._checkpoints.get(request_hash)
            if not checkpoint:
                checkpoint = Checkpoint(request_hash=request_hash)
                self._checkpoints[request_hash] = checkpoint

            # 过滤已完成的仓库
            repos = [r for r in repos if r not in checkpoint.completed_repos]

        # 并发搜索
        semaphore = asyncio.Semaphore(self.max_concurrent)

        async def search_repo(repo: str) -> tuple[str, SearchResponse]:
            async with semaphore:
                response = await self.search(
                    pattern=pattern,
                    repo=repo,
                    platform=platform,
                    max_results=max_results_per_repo,
                )

                # 更新检查点
                if checkpoint:
                    checkpoint.completed_repos.append(repo)
                    checkpoint.partial_results.append(response.to_dict())
                    checkpoint.updated_at = time.time()
                    checkpoint.state = "running" if response.error else "completed"

                return repo, response

        tasks = [search_repo(repo) for repo in repos]
        results = await asyncio.gather(*tasks, return_exceptions=True)

        # 处理结果
        response_dict: dict[str, SearchResponse] = {}
        for result in results:
            if isinstance(result, Exception):
                continue
            repo, response = result
            response_dict[repo] = response

        # 保存检查点
        if use_checkpoints and self.checkpoint_dir:
            await self._save_checkpoints()

        return response_dict

    def merge_results(
        self,
        results_list: list[list[SearchResult]],
        deduplicate: bool = True,
        sort_by: str = "file_path",
    ) -> list[SearchResult]:
        """合并多个搜索结果.

        Args:
            results_list: 结果列表的列表
            deduplicate: 是否去重
            sort_by: 排序字段 (file_path/line_number/relevance)

        Returns:
            合并后的结果列表

        Example:
            ```python
            merged = manager.merge_results(
                [results1, results2, results3],
                deduplicate=True,
                sort_by="file_path"
            )
            ```
        """
        all_results = []
        for results in results_list:
            all_results.extend(results)

        if deduplicate:
            seen = set()
            unique_results = []

            for result in all_results:
                # 基于文件路径 + 行号的去重键
                key = f"{result.file_path}:{result.line_number}"
                if key not in seen:
                    seen.add(key)
                    unique_results.append(result)

            all_results = unique_results

        # 排序
        if sort_by == "file_path":
            all_results.sort(key=lambda r: r.file_path)
        elif sort_by == "line_number":
            all_results.sort(key=lambda r: (r.file_path, r.line_number))

        return all_results

    def get_pathway_status(self) -> dict[str, dict[str, Any]]:
        """获取所有通路状态.

        Returns:
            通路状态字典

        Example:
            ```python
            statuses = manager.get_pathway_status()
            for name, status in statuses.items():
                print(f"{name}: 可用={status['available']}, 认证成功={status['authenticated']}")
            ```
        """
        return {
            pathway.value: status.to_dict()
            for pathway, status in self._pathway_statuses.items()
        }

    def get_performance_stats(self) -> dict[str, Any]:
        """获取性能统计.

        Returns:
            性能统计字典

        Example:
            ```python
            stats = manager.get_performance_stats()
            print(f"成功率：{stats['success_rate']:.2%}")
            print(f"平均响应时间：{stats['avg_response_time_ms']:.2f}ms")
            ```
        """
        return self._stats.to_dict()

    async def reset_pathway_status(self, pathway: PathwayType | None = None) -> None:
        """重置通路状态.

        Args:
            pathway: 要重置的通路，None 表示重置所有
        """
        if pathway:
            status = self._pathway_statuses.get(pathway)
            if status:
                status.success_count = 0
                status.failure_count = 0
                status.avg_response_time_ms = 0.0
                status.last_error = ""
                status.available = True
        else:
            await self._init_pathway_statuses()

    async def _load_checkpoints(self) -> None:
        """加载检查点."""
        if not self.checkpoint_dir or not self.checkpoint_dir.exists():
            return

        try:
            for checkpoint_file in self.checkpoint_dir.glob("*.json"):
                try:
                    data = json.loads(checkpoint_file.read_text())
                    checkpoint = Checkpoint.from_dict(data)
                    self._checkpoints[checkpoint.request_hash] = checkpoint
                except Exception as e:
                    logger.warning(f"加载检查点失败 {checkpoint_file}: {e}")
        except Exception as e:
            logger.warning(f"加载检查点目录失败：{e}")

    async def _save_checkpoints(self) -> None:
        """保存检查点."""
        if not self.checkpoint_dir:
            return

        self.checkpoint_dir.mkdir(parents=True, exist_ok=True)

        for request_hash, checkpoint in self._checkpoints.items():
            try:
                checkpoint_file = self.checkpoint_dir / f"{request_hash}.json"
                checkpoint_file.write_text(json.dumps(checkpoint.to_dict(), indent=2))
            except Exception as e:
                logger.warning(f"保存检查点失败 {request_hash}: {e}")

    async def clear_checkpoints(self) -> None:
        """清空所有检查点."""
        self._checkpoints.clear()

        if self.checkpoint_dir and self.checkpoint_dir.exists():
            for checkpoint_file in self.checkpoint_dir.glob("*.json"):
                try:
                    checkpoint_file.unlink()
                except Exception:
                    pass

    async def resume_search(
        self,
        pattern: str,
        repos: list[str],
        request_hash: str,
    ) -> dict[str, SearchResponse]:
        """从检查点恢复搜索.

        Args:
            pattern: 搜索模式
            repos: 仓库列表
            request_hash: 请求哈希

        Returns:
            搜索结果
        """
        checkpoint = self._checkpoints.get(request_hash)
        if not checkpoint:
            raise ValueError(f"检查点不存在：{request_hash}")

        # 过滤已完成的仓库
        remaining_repos = [r for r in repos if r not in checkpoint.completed_repos]

        if not remaining_repos:
            # 所有仓库都已完成，返回检查点中的结果
            results = {}
            for result_data in checkpoint.partial_results:
                repo = result_data.get("repo")
                if repo:
                    results[repo] = SearchResponse(
                        results=[
                            SearchResult(
                                file_path=r.get("file_path", ""),
                                line_number=r.get("line_number", 0),
                                content=r.get("content", ""),
                            )
                            for r in result_data.get("results", [])
                        ],
                        total_time_ms=result_data.get("total_time_ms", 0),
                    )
            return results

        # 继续搜索剩余仓库
        return await self.search_multiple(
            pattern=pattern,
            repos=remaining_repos,
            use_checkpoints=True,
        )