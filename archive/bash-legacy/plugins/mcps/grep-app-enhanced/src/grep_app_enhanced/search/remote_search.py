"""
Remote Search - 远程仓库搜索模块（增强版：三层缓存）.

本模块提供远程 Git 仓库的搜索功能，支持三层缓存架构：
- L1: SQLite+ZSTD 压缩缓存（最快，命中率目标>80%）
- L2: 本地 Git 仓库缓存（中等速度）
- L3: 远程通路查询（最完整，最慢）

Example:
    ```python
    from grep_app_enhanced.search import RemoteSearch

    search = RemoteSearch(token="ghp_xxx")
    results = await search.search_with_three_layer_cache(
        "def main",
        repo="owner/repo",
        platform="github"
    )
    ```

Supported Platforms:
    - GitHub: 使用 API 和 CLI
    - GitLab: 使用 API
    - Generic: 通过 Git 克隆

Cache Layers:
    - L1: SQLite+ZSTD 压缩缓存 (毫秒级响应)
    - L2: 本地 Git 仓库缓存 (秒级响应)
    - L3: 远程通路查询 (依赖网络)

Search Strategies:
    - api: 使用平台 API（快速，有限制）
    - clone: 克隆后本地搜索（完整，较慢）
    - hybrid: 混合模式（推荐）

Author:
    Oh My LiteCode Team
"""

from __future__ import annotations

import asyncio
import hashlib
import json
import logging
import os
import tempfile
import time
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Any, Optional

from ..__init__ import SearchResult
from ..database import CacheManager, CompressedDatabase
from ..remote import GitHubCLI, GitClient, GitCrawler

logger = logging.getLogger(__name__)


class CacheLayer(Enum):
    """缓存层级枚举."""

    L1 = "l1_sqlite_zstd"  # SQLite+ZSTD 压缩缓存
    L2 = "l2_git_repo"  # 本地 Git 仓库缓存
    L3 = "l3_remote"  # 远程通路查询


@dataclass
class ThreeLayerCacheStats:
    """三层缓存统计数据类.

    Attributes:
        l1_hits: L1 缓存命中次数
        l1_misses: L1 缓存未命中次数
        l2_hits: L2 缓存命中次数
        l2_misses: L2 缓存未命中次数
        l3_queries: L3 查询次数
        total_time_ms: 总耗时（毫秒）
        l1_time_ms: L1 查询耗时
        l2_time_ms: L2 查询耗时
        l3_time_ms: L3 查询耗时
        cache_fill_backs: 缓存回填次数

    Example:
        ```python
        stats = ThreeLayerCacheStats()
        print(f"L1 命中率：{stats.l1_hit_rate:.2%}")
        ```
    """

    l1_hits: int = 0
    l1_misses: int = 0
    l2_hits: int = 0
    l2_misses: int = 0
    l3_queries: int = 0
    total_time_ms: float = 0.0
    l1_time_ms: float = 0.0
    l2_time_ms: float = 0.0
    l3_time_ms: float = 0.0
    cache_fill_backs: int = 0

    @property
    def l1_hit_rate(self) -> float:
        """计算 L1 命中率."""
        total = self.l1_hits + self.l1_misses
        if total == 0:
            return 0.0
        return self.l1_hits / total

    @property
    def l2_hit_rate(self) -> float:
        """计算 L2 命中率."""
        total = self.l2_hits + self.l2_misses
        if total == 0:
            return 0.0
        return self.l2_hits / total

    @property
    def overall_hit_rate(self) -> float:
        """计算整体缓存命中率."""
        total_hits = self.l1_hits + self.l2_hits
        total_queries = self.l1_hits + self.l1_misses
        if total_queries == 0:
            return 0.0
        return total_hits / total_queries

    def to_dict(self) -> dict[str, Any]:
        """转换为字典格式."""
        return {
            "l1_hits": self.l1_hits,
            "l1_misses": self.l1_misses,
            "l1_hit_rate": round(self.l1_hit_rate, 4),
            "l2_hits": self.l2_hits,
            "l2_misses": self.l2_misses,
            "l2_hit_rate": round(self.l2_hit_rate, 4),
            "l3_queries": self.l3_queries,
            "overall_hit_rate": round(self.overall_hit_rate, 4),
            "total_time_ms": round(self.total_time_ms, 2),
            "l1_time_ms": round(self.l1_time_ms, 2),
            "l2_time_ms": round(self.l2_time_ms, 2),
            "l3_time_ms": round(self.l3_time_ms, 2),
            "cache_fill_backs": self.cache_fill_backs,
        }


@dataclass
class CacheEntry:
    """缓存条目数据类.

    Attributes:
        key: 缓存键
        data: 缓存数据
        created_at: 创建时间戳
        expires_at: 过期时间戳
        layer: 缓存层级
        metadata: 额外元数据
    """

    key: str
    data: list[SearchResult]
    created_at: float
    expires_at: float
    layer: CacheLayer
    metadata: dict[str, Any] = field(default_factory=dict)

    def is_expired(self) -> bool:
        """检查是否已过期."""
        return time.time() > self.expires_at

    def to_dict(self) -> dict[str, Any]:
        """转换为字典格式."""
        return {
            "key": self.key,
            "data": [r.to_dict() for r in self.data],
            "created_at": self.created_at,
            "expires_at": self.expires_at,
            "layer": self.layer.value,
            "metadata": self.metadata,
        }

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> CacheEntry:
        """从字典创建实例."""
        return cls(
            key=d["key"],
            data=[SearchResult(**r) for r in d["data"]],
            created_at=d["created_at"],
            expires_at=d["expires_at"],
            layer=CacheLayer(d["layer"]),
            metadata=d.get("metadata", {}),
        )


@dataclass
class RemoteSearchConfig:
    """远程搜索配置数据类.

    Attributes:
        repo: 仓库标识 (owner/repo)
        platform: 平台名称
        ref: 分支/标签/提交
        path: 搜索路径过滤
        language: 语言过滤
        use_api: 是否使用 API
        use_cache: 是否使用缓存
        cache_ttl: 缓存生存时间
        clone_depth: 克隆深度（0 表示完整克隆）

    Example:
        ```python
        config = RemoteSearchConfig(
            repo="microsoft/vscode",
            platform="github",
            ref="main",
            language="TypeScript"
        )
        ```
    """

    repo: str
    platform: str = "github"
    ref: str = "HEAD"
    path: str = ""
    language: str | None = None
    use_api: bool = True
    use_cache: bool = True
    cache_ttl: int = 3600
    clone_depth: int = 1


@dataclass
class SearchStatistics:
    """搜索统计数据类.

    Attributes:
        api_calls: API 调用次数
        files_searched: 搜索的文件数
        cache_hits: 缓存命中数
        cache_misses: 缓存未命中数
        total_time_ms: 总耗时（毫秒）

    Example:
        ```python
        stats = SearchStatistics()
        print(f"API 调用：{stats.api_calls}")
        ```
    """

    api_calls: int = 0
    files_searched: int = 0
    cache_hits: int = 0
    cache_misses: int = 0
    total_time_ms: float = 0.0

    def to_dict(self) -> dict[str, Any]:
        """转换为字典格式."""
        return {
            "api_calls": self.api_calls,
            "files_searched": self.files_searched,
            "cache_hits": self.cache_hits,
            "cache_misses": self.cache_misses,
            "total_time_ms": self.total_time_ms,
        }


class RemoteSearch:
    """远程仓库搜索类.

    提供对远程 Git 仓库的搜索功能，
    支持多个平台和多种搜索策略.

    Attributes:
        token: API Token
        cache_manager: 缓存管理器
        default_platform: 默认平台

    Example:
        ```python
        search = RemoteSearch(
            token="ghp_xxx",
            use_cache=True
        )
        await search.initialize()

        results = await search.search(
            "TODO",
            repo="owner/repo",
            platform="github"
        )
        ```

    Note:
        - API 搜索有速率限制
        - 克隆搜索需要磁盘空间
        - 缓存可以显著提高性能
    """

    SUPPORTED_PLATFORMS = {"github", "gitlab", "gitee", "generic"}

    def __init__(
        self,
        token: str | None = None,
        use_cache: bool = True,
        cache_ttl: int = 3600,
        max_cache_size: int = 1000,
        default_platform: str = "github",
        db_path: str | Path | None = None,
        git_cache_dir: str | Path | None = None,
    ) -> None:
        """初始化远程搜索.

        Args:
            token: API Token
            use_cache: 是否使用缓存
            cache_ttl: 缓存生存时间（秒）
            max_cache_size: 最大缓存条目数
            default_platform: 默认平台
            db_path: L1 SQLite 数据库路径
            git_cache_dir: L2 Git 缓存目录

        Raises:
            ValueError: 参数值无效
        """
        self.token = token
        self.use_cache = use_cache
        self.cache_ttl = cache_ttl
        self.max_cache_size = max_cache_size
        self.default_platform = default_platform
        self.db_path = Path(db_path) if db_path else None
        self.git_cache_dir = Path(git_cache_dir) if git_cache_dir else None

        self._github: GitHubCLI | None = None
        self._git: GitClient | None = None
        self._crawler: GitCrawler | None = None
        self._cache: CacheManager | None = None  # L1 内存缓存
        self._db: CompressedDatabase | None = None  # L1 SQLite+ZSTD 缓存
        self._stats = SearchStatistics()
        self._three_layer_stats = ThreeLayerCacheStats()
        self._temp_dirs: list[tempfile.TemporaryDirectory] = []
        self._git_repos: dict[str, Path] = {}  # L2 Git 仓库缓存映射

    async def initialize(self) -> None:
        """初始化客户端和三层缓存.

        初始化顺序：
        1. GitHub CLI 客户端
        2. Git 客户端
        3. Crawler 客户端
        4. L1 内存缓存
        5. L1 SQLite+ZSTD 数据库缓存
        6. L2 Git 仓库缓存目录
        """
        # 初始化客户端
        self._github = GitHubCLI(token=self.token)
        await self._github.initialize()

        self._git = GitClient()
        self._crawler = GitCrawler(token=self.token)
        await self._crawler.initialize()

        # 初始化 L1 内存缓存
        if self.use_cache:
            self._cache = CacheManager(
                ttl=self.cache_ttl,
                max_size=self.max_cache_size,
            )
            await self._cache.initialize()

        # 初始化 L1 SQLite+ZSTD 数据库缓存
        if self.db_path:
            self.db_path.parent.mkdir(parents=True, exist_ok=True)
            self._db = CompressedDatabase(
                db_path=self.db_path,
                compression_level=3,  # 快速压缩
            )
            await self._db.initialize()
            logger.info(f"L1 SQLite 缓存初始化：{self.db_path}")

        # 初始化 L2 Git 仓库缓存目录
        if self.git_cache_dir:
            self.git_cache_dir.mkdir(parents=True, exist_ok=True)
            logger.info(f"L2 Git 缓存目录：{self.git_cache_dir}")

        logger.info("RemoteSearch 三层缓存初始化完成")

    async def close(self) -> None:
        """关闭客户端并清理资源."""
        if self._github:
            await self._github.close()
        if self._crawler:
            await self._crawler.close()
        if self._cache:
            await self._cache.close()
        if self._db:
            await self._db.close()

        # 清理临时目录
        for temp_dir in self._temp_dirs:
            try:
                temp_dir.cleanup()
            except Exception:
                pass
        self._temp_dirs.clear()

        logger.info("RemoteSearch 已关闭")

    async def __aenter__(self) -> RemoteSearch:
        """异步上下文管理器入口."""
        await self.initialize()
        return self

    async def __aexit__(self, exc_type: Any, exc_val: Any, exc_tb: Any) -> None:
        """异步上下文管理器出口."""
        await self.close()

    # =========================================================================
    # 三层缓存核心方法
    # =========================================================================

    async def _query_l1(
        self,
        cache_key: str,
    ) -> tuple[list[SearchResult] | None, float]:
        """L1: SQLite+ZSTD 缓存查询.

        查询顺序：
        1. 内存缓存（最快）
        2. SQLite+ZSTD 压缩数据库缓存

        Args:
            cache_key: 缓存键

        Returns:
            (搜索结果，查询耗时 ms)
        """
        start_time = time.perf_counter()

        # 先查内存缓存
        if self._cache:
            cached = await self._cache.get(cache_key)
            if cached:
                elapsed = (time.perf_counter() - start_time) * 1000
                self._three_layer_stats.l1_hits += 1
                self._three_layer_stats.l1_time_ms += elapsed
                logger.debug(f"L1 内存缓存命中：{cache_key[:16]}... ({elapsed:.2f}ms)")
                return cached, elapsed

        # 再查 SQLite+ZSTD 缓存
        if self._db:
            try:
                query_hash = hashlib.sha256(cache_key.encode()).hexdigest()[:32]
                results, stats = await self._db.retrieve_search_results(query_hash)
                elapsed = (time.perf_counter() - start_time) * 1000

                if results:
                    self._three_layer_stats.l1_hits += 1
                    self._three_layer_stats.l1_time_ms += elapsed
                    logger.debug(f"L1 SQLite 缓存命中：{cache_key[:16]}... ({elapsed:.2f}ms)")

                    # 回填到内存缓存
                    if self._cache:
                        await self._cache.set(cache_key, results, ttl=self.cache_ttl)

                    return results, elapsed
                else:
                    self._three_layer_stats.l1_misses += 1
                    self._three_layer_stats.l1_time_ms += elapsed
                    logger.debug(f"L1 缓存未命中：{cache_key[:16]}...")
                    return None, elapsed

            except Exception as e:
                logger.warning(f"L1 SQLite 查询失败：{e}")
                self._three_layer_stats.l1_misses += 1

        self._three_layer_stats.l1_misses += 1
        elapsed = (time.perf_counter() - start_time) * 1000
        self._three_layer_stats.l1_time_ms += elapsed
        return None, elapsed

    async def _query_l2(
        self,
        pattern: str,
        config: RemoteSearchConfig,
    ) -> tuple[list[SearchResult] | None, float]:
        """L2: 本地 Git 仓库缓存查询.

        在本地 Git 仓库缓存中搜索，适用于频繁访问的仓库.

        Args:
            pattern: 搜索模式
            config: 搜索配置

        Returns:
            (搜索结果，查询耗时 ms)
        """
        start_time = time.perf_counter()

        if not self.git_cache_dir or not self._git:
            elapsed = (time.perf_counter() - start_time) * 1000
            self._three_layer_stats.l2_misses += 1
            self._three_layer_stats.l2_time_ms += elapsed
            return None, elapsed

        # 构建仓库缓存路径
        repo_safe_name = config.repo.replace("/", "_")
        repo_path = self.git_cache_dir / repo_safe_name

        # 检查仓库是否存在
        if not repo_path.exists():
            elapsed = (time.perf_counter() - start_time) * 1000
            self._three_layer_stats.l2_misses += 1
            self._three_layer_stats.l2_time_ms += elapsed
            logger.debug(f"L2 Git 仓库不存在：{config.repo}")
            return None, elapsed

        # 检查是否为 Git 仓库
        if not await self._git.is_git_repo(repo_path):
            elapsed = (time.perf_counter() - start_time) * 1000
            self._three_layer_stats.l2_misses += 1
            self._three_layer_stats.l2_time_ms += elapsed
            return None, elapsed

        try:
            # 在 Git 仓库中搜索
            results = await self._git.search_in_repo(
                repo_path=repo_path,
                pattern=pattern,
                extensions=[f".{config.language.lower()}"] if config.language else None,
                max_results=100,
            )

            elapsed = (time.perf_counter() - start_time) * 1000
            self._three_layer_stats.l2_time_ms += elapsed

            if results:
                self._three_layer_stats.l2_hits += 1

                # 转换为 SearchResult
                search_results = []
                for r in results:
                    try:
                        rel_path = str(Path(r["file"]).relative_to(repo_path))
                    except ValueError:
                        rel_path = r["file"]

                    search_results.append(
                        SearchResult(
                            file_path=rel_path,
                            line_number=r.get("line", 0),
                            content=r.get("content", ""),
                            metadata={
                                "repository": config.repo,
                                "platform": config.platform,
                                "cache_layer": "l2_git",
                            },
                        )
                    )

                logger.debug(f"L2 Git 缓存命中：{config.repo} ({elapsed:.2f}ms)")
                return search_results, elapsed
            else:
                self._three_layer_stats.l2_misses += 1
                logger.debug(f"L2 Git 缓存未命中：{config.repo}")
                return None, elapsed

        except Exception as e:
            logger.warning(f"L2 Git 查询失败：{e}")
            self._three_layer_stats.l2_misses += 1
            elapsed = (time.perf_counter() - start_time) * 1000
            self._three_layer_stats.l2_time_ms += elapsed
            return None, elapsed

    async def _query_l3(
        self,
        pattern: str,
        config: RemoteSearchConfig,
    ) -> tuple[list[SearchResult], float]:
        """L3: 远程通路查询.

        这是最后一层，直接查询远程仓库.

        Args:
            pattern: 搜索模式
            config: 搜索配置

        Returns:
            (搜索结果，查询耗时 ms)
        """
        start_time = time.perf_counter()
        self._three_layer_stats.l3_queries += 1

        try:
            # 优先使用 API
            if config.use_api and config.platform == "github":
                results = await self._search_with_api(pattern, config)
            else:
                # 尝试 API，失败则回退到克隆
                try:
                    results = await self._search_with_api(pattern, config)
                except Exception:
                    results = await self._search_with_clone(pattern, config)
        except Exception as e:
            logger.warning(f"L3 API/Clone 失败，回退到爬虫：{e}")
            # 最后回退到爬虫
            results = await self._search_with_crawler(pattern, config)

        elapsed = (time.perf_counter() - start_time) * 1000
        self._three_layer_stats.l3_time_ms += elapsed
        logger.debug(f"L3 远程查询完成：{config.repo} ({elapsed:.2f}ms)")

        return results, elapsed

    async def _fill_back_cache(
        self,
        cache_key: str,
        results: list[SearchResult],
        config: RemoteSearchConfig,
    ) -> None:
        """缓存回填.

        将 L3 查询结果回填到 L1 和 L2 缓存.

        Args:
            cache_key: 缓存键
            results: 搜索结果
            config: 搜索配置
        """
        if not results:
            return

        # 回填到 L1 内存缓存
        if self._cache:
            try:
                await self._cache.set(cache_key, results, ttl=config.cache_ttl)
            except Exception as e:
                logger.warning(f"L1 内存缓存回填失败：{e}")

        # 回填到 L1 SQLite 缓存
        if self._db:
            try:
                query_hash = hashlib.sha256(cache_key.encode()).hexdigest()[:32]
                await self._db.store_search_results(
                    query_hash=query_hash,
                    pattern=config.repo,
                    search_path=config.path or "/",
                    results=results,
                    ttl_seconds=config.cache_ttl,
                )
            except Exception as e:
                logger.warning(f"L1 SQLite 缓存回填失败：{e}")

        # 回填到 L2 Git 缓存（如果需要）
        if self.git_cache_dir and self._git:
            try:
                repo_safe_name = config.repo.replace("/", "_")
                repo_path = self.git_cache_dir / repo_safe_name

                if not repo_path.exists():
                    # 克隆仓库到缓存目录
                    if config.platform == "github":
                        clone_url = f"https://github.com/{config.repo}.git"
                    elif config.platform == "gitlab":
                        clone_url = f"https://gitlab.com/{config.repo}.git"
                    elif config.platform == "gitee":
                        clone_url = f"https://gitee.com/{config.repo}.git"
                    else:
                        clone_url = config.repo

                    await self._git.clone_repository(
                        url=clone_url,
                        dest=repo_path,
                        depth=1,
                        timeout=120,
                    )
                    self._git_repos[config.repo] = repo_path
                    logger.info(f"L2 Git 缓存已创建：{repo_path}")

                self._three_layer_stats.cache_fill_backs += 1

            except Exception as e:
                logger.warning(f"L2 Git 缓存回填失败：{e}")

    async def search_with_three_layer_cache(
        self,
        pattern: str,
        repo: str,
        platform: str | None = None,
        ref: str = "HEAD",
        path: str = "",
        language: str | None = None,
        use_api: bool = True,
        max_results: int = 100,
        cache_ttl: int | None = None,
    ) -> tuple[list[SearchResult], ThreeLayerCacheStats]:
        """三层缓存搜索.

        搜索流程：
        1. L1: 查询 SQLite+ZSTD 压缩缓存（最快，命中率目标>80%）
        2. L2: 查询本地 Git 仓库缓存（中等速度）
        3. L3: 远程通路查询（最完整，最慢）
        4. 缓存回填：将 L3 结果回填到 L1/L2

        Args:
            pattern: 搜索模式
            repo: 仓库标识 (owner/repo)
            platform: 平台名称
            ref: 分支/标签/提交
            path: 搜索路径过滤
            language: 语言过滤
            use_api: 是否使用 API
            max_results: 最大返回结果数
            cache_ttl: 缓存生存时间（秒）

        Returns:
            (搜索结果列表，三层缓存统计)

        Example:
            ```python
            search = RemoteSearch(
                token="ghp_xxx",
                db_path="/tmp/grep.db",
                git_cache_dir="/tmp/git-cache"
            )
            await search.initialize()

            results, stats = await search.search_with_three_layer_cache(
                "def main",
                repo="microsoft/vscode",
                platform="github",
                language="TypeScript"
            )
            print(f"L1 命中率：{stats.l1_hit_rate:.2%}")
            print(f"总耗时：{stats.total_time_ms:.2f}ms")
            ```
        """
        total_start = time.perf_counter()
        platform = platform or self.default_platform

        if platform not in self.SUPPORTED_PLATFORMS:
            raise ValueError(f"不支持的平台：{platform}")

        # 创建配置
        config = RemoteSearchConfig(
            repo=repo,
            platform=platform,
            ref=ref,
            path=path,
            language=language,
            use_api=use_api,
            cache_ttl=cache_ttl or self.cache_ttl,
        )

        # 计算缓存键
        cache_key = self._compute_cache_key(pattern, repo, ref, path, platform)

        # L1: 查询 SQLite+ZSTD 缓存
        l1_results, l1_time = await self._query_l1(cache_key)
        if l1_results:
            self._three_layer_stats.total_time_ms = (time.perf_counter() - total_start) * 1000
            return l1_results[:max_results], self._three_layer_stats

        # L2: 查询本地 Git 仓库缓存
        l2_results, l2_time = await self._query_l2(pattern, config)
        if l2_results:
            # 回填到 L1
            await self._fill_back_cache(cache_key, l2_results, config)
            self._three_layer_stats.total_time_ms = (time.perf_counter() - total_start) * 1000
            return l2_results[:max_results], self._three_layer_stats

        # L3: 远程通路查询
        l3_results, l3_time = await self._query_l3(pattern, config)
        l3_results = l3_results[:max_results]

        # 缓存回填
        await self._fill_back_cache(cache_key, l3_results, config)

        # 更新统计
        self._three_layer_stats.total_time_ms = (time.perf_counter() - total_start) * 1000
        self._stats.files_searched = len(set(r.file_path for r in l3_results))
        self._stats.total_time_ms = self._three_layer_stats.total_time_ms

        return l3_results, self._three_layer_stats

    def _compute_cache_key(
        self,
        pattern: str,
        repo: str,
        ref: str,
        path: str,
        platform: str,
    ) -> str:
        """计算缓存键.

        Args:
            pattern: 搜索模式
            repo: 仓库标识
            ref: 引用
            path: 路径
            platform: 平台

        Returns:
            缓存键
        """
        key_str = f"{platform}:{repo}:{ref}:{path}:{pattern}"
        return hashlib.sha256(key_str.encode()).hexdigest()

    def _convert_github_result(
        self,
        code_result: Any,
        content: str | None = None,
    ) -> SearchResult:
        """转换 GitHub 搜索结果.

        Args:
            code_result: GitHub API 返回的结果
            content: 文件内容

        Returns:
            SearchResult 实例
        """
        from ..remote.gh_cli import CodeSearchResult

        if isinstance(code_result, CodeSearchResult):
            return SearchResult(
                file_path=code_result.path,
                line_number=code_result.matches[0].get("line_number", 0)
                if code_result.matches
                else 0,
                content=content or "",
                metadata={
                    "repository": code_result.repository,
                    "url": code_result.url,
                },
            )

        # 通用转换
        return SearchResult(
            file_path=getattr(code_result, "path", ""),
            line_number=getattr(code_result, "line_number", 0),
            content=getattr(code_result, "content", ""),
            metadata={"repository": getattr(code_result, "repository", "")},
        )

    async def _search_with_api(
        self,
        pattern: str,
        config: RemoteSearchConfig,
    ) -> list[SearchResult]:
        """使用 API 搜索.

        Args:
            pattern: 搜索模式
            config: 搜索配置

        Returns:
            搜索结果列表
        """
        if config.platform == "github" and self._github:
            self._stats.api_calls += 1

            # 解析 repo
            parts = config.repo.split("/")
            if len(parts) != 2:
                raise ValueError(f"无效的仓库标识：{config.repo}")

            owner, repo = parts

            results = await self._github.search_code(
                query=pattern,
                owner=owner,
                repo=repo,
                language=config.language,
                path=config.path if config.path else None,
            )

            # 获取文件内容
            search_results = []
            for result in results:
                try:
                    content = await self._github.get_file_content(
                        owner=owner,
                        repo=repo,
                        path=result.path,
                        ref=config.ref,
                    )
                    search_results.append(
                        self._convert_github_result(result, content)
                    )
                except Exception:
                    search_results.append(self._convert_github_result(result))

            return search_results

        elif config.platform in ("gitlab", "gitee"):
            # 这些平台回退到爬虫方式
            return await self._search_with_crawler(pattern, config)

        else:
            raise ValueError(f"不支持的平台：{config.platform}")

    async def _search_with_crawler(
        self,
        pattern: str,
        config: RemoteSearchConfig,
    ) -> list[SearchResult]:
        """使用爬虫搜索.

        Args:
            pattern: 搜索模式
            config: 搜索配置

        Returns:
            搜索结果列表
        """
        if not self._crawler:
            raise RuntimeError("爬虫未初始化")

        # 构建仓库 URL
        if config.platform == "github":
            repo_url = f"https://github.com/{config.repo}"
        elif config.platform == "gitlab":
            repo_url = f"https://gitlab.com/{config.repo}"
        elif config.platform == "gitee":
            repo_url = f"https://gitee.com/{config.repo}"
        else:
            repo_url = config.repo

        # 列出目录并搜索
        try:
            files = await self._crawler.list_directory(
                repo_url=repo_url,
                ref=config.ref,
                path=config.path,
            )

            results = []
            for file in files:
                if file.is_file:
                    # 检查扩展名
                    if config.language:
                        lang_extensions = {
                            "python": [".py"],
                            "javascript": [".js", ".jsx", ".mjs"],
                            "typescript": [".ts", ".tsx"],
                            "go": [".go"],
                            "rust": [".rs"],
                            "java": [".java"],
                            "c": [".c", ".h"],
                            "cpp": [".cpp", ".hpp", ".cc", ".cxx"],
                        }
                        exts = lang_extensions.get(config.language.lower(), [])
                        if exts and Path(file.name).suffix not in exts:
                            continue

                    try:
                        content = await self._crawler.fetch_file(
                            repo_url=repo_url,
                            ref=config.ref,
                            path=file.path,
                        )

                        # 本地搜索内容
                        import re

                        for line_num, line in enumerate(content.splitlines(), 1):
                            if re.search(pattern, line, re.IGNORECASE):
                                results.append(
                                    SearchResult(
                                        file_path=file.path,
                                        line_number=line_num,
                                        content=line,
                                        metadata={
                                            "repository": config.repo,
                                            "platform": config.platform,
                                        },
                                    )
                                )
                    except Exception:
                        pass

            return results

        except Exception as e:
            raise RuntimeError(f"爬虫搜索失败：{e}")

    async def _search_with_clone(
        self,
        pattern: str,
        config: RemoteSearchConfig,
    ) -> list[SearchResult]:
        """通过克隆仓库搜索.

        Args:
            pattern: 搜索模式
            config: 搜索配置

        Returns:
            搜索结果列表
        """
        if not self._git:
            raise RuntimeError("Git 客户端未初始化")

        # 创建临时目录
        temp_dir = tempfile.TemporaryDirectory()
        self._temp_dirs.append(temp_dir)

        try:
            # 构建克隆 URL
            if config.platform == "github":
                clone_url = f"https://github.com/{config.repo}.git"
            elif config.platform == "gitlab":
                clone_url = f"https://gitlab.com/{config.repo}.git"
            elif config.platform == "gitee":
                clone_url = f"https://gitee.com/{config.repo}.git"
            else:
                clone_url = config.repo

            # 克隆仓库
            clone_args = [clone_url, temp_dir.name]
            if config.clone_depth > 0:
                clone_args.insert(1, f"--depth={config.clone_depth}")
            if config.ref and config.ref != "HEAD":
                clone_args.insert(1, "-b")
                clone_args.insert(2, config.ref)

            await self._git._run_command(["clone"] + clone_args[1:])

            # 本地搜索
            from .local_search import LocalSearch

            async with LocalSearch() as local_search:
                results = await local_search.search(
                    pattern=pattern,
                    path=temp_dir.name,
                    include=["*"],
                    exclude=[".git"],
                )

                # 更新文件路径为相对路径
                for result in results:
                    try:
                        result.file_path = str(
                            Path(result.file_path).relative_to(temp_dir.name)
                        )
                    except ValueError:
                        pass

                    result.metadata["repository"] = config.repo
                    result.metadata["platform"] = config.platform

                return results

        finally:
            # 不立即清理，留给后续使用
            pass

    async def search(
        self,
        pattern: str,
        repo: str,
        platform: str | None = None,
        ref: str = "HEAD",
        path: str = "",
        language: str | None = None,
        use_api: bool = True,
        max_results: int = 100,
    ) -> list[SearchResult]:
        """执行远程搜索.

        Args:
            pattern: 搜索模式
            repo: 仓库标识 (owner/repo)
            platform: 平台名称
            ref: 分支/标签/提交
            path: 搜索路径过滤
            language: 语言过滤
            use_api: 是否使用 API
            max_results: 最大返回结果数

        Returns:
            搜索结果列表

        Example:
            ```python
            search = RemoteSearch(token="ghp_xxx")
            await search.initialize()

            results = await search.search(
                "def main",
                repo="microsoft/vscode",
                platform="github",
                language="TypeScript"
            )
            ```
        """
        import time

        start_time = time.perf_counter()
        platform = platform or self.default_platform

        if platform not in self.SUPPORTED_PLATFORMS:
            raise ValueError(f"不支持的平台：{platform}")

        # 创建配置
        config = RemoteSearchConfig(
            repo=repo,
            platform=platform,
            ref=ref,
            path=path,
            language=language,
            use_api=use_api,
        )

        # 检查缓存
        cache_key = None
        if self._cache and config.use_cache:
            cache_key = self._compute_cache_key(
                pattern, repo, ref, path, platform
            )
            cached = await self._cache.get(cache_key)
            if cached:
                self._stats.cache_hits += 1
                self._stats.total_time_ms = (time.perf_counter() - start_time) * 1000
                return cached

            self._stats.cache_misses += 1

        # 执行搜索
        try:
            if use_api and platform == "github":
                results = await self._search_with_api(pattern, config)
            else:
                # 尝试 API，失败则回退到克隆
                try:
                    results = await self._search_with_api(pattern, config)
                except Exception:
                    results = await self._search_with_clone(pattern, config)
        except Exception as e:
            # 最后回退到爬虫
            results = await self._search_with_crawler(pattern, config)

        # 限制结果数
        results = results[:max_results]

        # 更新统计
        self._stats.files_searched = len(set(r.file_path for r in results))
        self._stats.total_time_ms = (time.perf_counter() - start_time) * 1000

        # 缓存结果
        if self._cache and cache_key and results:
            await self._cache.set(cache_key, results, ttl=config.cache_ttl)

        return results

    async def search_multiple(
        self,
        pattern: str,
        repos: list[str],
        platform: str | None = None,
        max_results_per_repo: int = 50,
    ) -> dict[str, list[SearchResult]]:
        """在多个仓库中搜索.

        Args:
            pattern: 搜索模式
            repos: 仓库列表
            platform: 平台名称
            max_results_per_repo: 每个仓库的最大结果数

        Returns:
            仓库到结果的映射
        """
        tasks = [
            self.search(
                pattern=pattern,
                repo=repo,
                platform=platform,
                max_results=max_results_per_repo,
            )
            for repo in repos
        ]

        results = await asyncio.gather(*tasks, return_exceptions=True)

        return {
            repo: result if isinstance(result, list) else []
            for repo, result in zip(repos, results)
        }

    def get_three_layer_stats(self) -> ThreeLayerCacheStats:
        """获取三层缓存统计.

        Returns:
            三层缓存统计数据
        """
        return self._three_layer_stats

    def reset_three_layer_stats(self) -> None:
        """重置三层缓存统计."""
        self._three_layer_stats = ThreeLayerCacheStats()

    def get_statistics(self) -> SearchStatistics:
        """获取搜索统计.

        Returns:
            统计数据
        """
        return self._stats

    async def clear_cache(self) -> None:
        """清空缓存."""
        if self._cache:
            await self._cache.clear()
