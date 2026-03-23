"""
MCP Server - 增强版 grep-app MCP 服务器入口（三层缓存 + 智能降级）.

本模块提供基于 MCP (Model Context Protocol) 协议的服务器实现，
支持以下功能：
- 本地文件搜索
- 远程仓库搜索（三层缓存）
- 智能降级策略
- 缓存管理
- 数据库操作
- 性能监控

Example:
    ```bash
    # 直接运行
    python -m grep_app_enhanced.mcp_server

    # 使用 MCP 协议
    mcp run grep-app-enhanced
    ```

MCP Tools:
    - search_local: 本地文件搜索
    - search_remote: 远程仓库搜索（三层缓存）
    - search_with_fallback: 带智能降级的搜索
    - get_cache_stats: 获取缓存统计
    - get_three_layer_stats: 获取三层缓存统计
    - get_fallback_metrics: 获取降级通路指标
    - clear_cache: 清空缓存
    - get_db_stats: 获取数据库统计
    - health_check: 健康检查端点

Configuration:
    通过环境变量配置：
    - GREP_APP_CACHE_DIR: 缓存目录
    - GREP_APP_DB_PATH: 数据库路径
    - GREP_APP_GIT_CACHE_DIR: Git 缓存目录
    - GITHUB_TOKEN: GitHub Token
    - GREP_APP_MAX_WORKERS: 最大工作线程数
    - GREP_APP_FALLBACK_ENABLED: 启用智能降级

Author:
    Oh My LiteCode Team
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import sys
import time
from pathlib import Path
from typing import Any

import click
from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import (
    Tool,
    TextContent,
    CallToolResult,
)

from .__init__ import GrepAppEnhanced, SearchConfig, SearchResult, __version__
from .database import CompressedDatabase, CacheManager
from .search import (
    LocalSearch,
    RemoteSearch,
    FallbackStrategy,
    FallbackConfig,
    ThreeLayerCacheStats,
    DEFAULT_FALLBACK_CONFIG,
)

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger("grep-app-enhanced")


class GrepAppMCPServer:
    """Grep App MCP 服务器（增强版：三层缓存 + 智能降级）.

    封装 MCP 服务器功能，提供搜索、缓存、数据库和智能降级操作.

    Attributes:
        cache_dir: 缓存目录
        db_path: 数据库路径
        git_cache_dir: Git 缓存目录
        github_token: GitHub Token
        max_workers: 最大工作线程数
        fallback_enabled: 是否启用智能降级

    Example:
        ```python
        server = GrepAppMCPServer(
            cache_dir="/tmp/grep-app-cache",
            db_path="/tmp/grep-app.db",
            git_cache_dir="/tmp/git-cache",
            fallback_enabled=True
        )
        await server.initialize()
        ```
    """

    def __init__(
        self,
        cache_dir: str | None = None,
        db_path: str | None = None,
        git_cache_dir: str | None = None,
        github_token: str | None = None,
        max_workers: int = 4,
        fallback_enabled: bool = True,
        fallback_config: FallbackConfig | None = None,
    ) -> None:
        """初始化 MCP 服务器.

        Args:
            cache_dir: 缓存目录
            db_path: 数据库路径
            git_cache_dir: Git 缓存目录
            github_token: GitHub Token
            max_workers: 最大工作线程数
            fallback_enabled: 是否启用智能降级
            fallback_config: 降级配置
        """
        self.cache_dir = Path(cache_dir) if cache_dir else None
        self.db_path = Path(db_path) if db_path else None
        self.git_cache_dir = Path(git_cache_dir) if git_cache_dir else None
        self.github_token = github_token or os.environ.get("GITHUB_TOKEN")
        self.max_workers = max_workers
        self.fallback_enabled = fallback_enabled
        self.fallback_config = fallback_config or DEFAULT_FALLBACK_CONFIG

        self._local_search: LocalSearch | None = None
        self._remote_search: RemoteSearch | None = None
        self._fallback_strategy: FallbackStrategy | None = None
        self._cache: CacheManager | None = None
        self._database: CompressedDatabase | None = None
        self._initialized = False

        # 性能监控
        self._request_count = 0
        self._error_count = 0
        self._total_response_time_ms = 0.0
        self._start_time = time.time()

    async def initialize(self) -> None:
        """初始化服务器组件.

        初始化顺序：
        1. 本地搜索
        2. 远程搜索（三层缓存）
        3. 智能降级策略
        4. 缓存管理器
        5. 压缩数据库
        """
        if self._initialized:
            return

        # 初始化本地搜索
        self._local_search = LocalSearch(max_workers=self.max_workers)

        # 初始化远程搜索（三层缓存）
        self._remote_search = RemoteSearch(
            token=self.github_token,
            use_cache=True,
            db_path=self.db_path,
            git_cache_dir=self.git_cache_dir,
        )
        await self._remote_search.initialize()

        # 初始化智能降级策略
        if self.fallback_enabled:
            self._fallback_strategy = FallbackStrategy(config=self.fallback_config)
            await self._fallback_strategy.initialize()
            logger.info("智能降级策略已启用")

        # 初始化缓存
        if self.cache_dir:
            self.cache_dir.mkdir(parents=True, exist_ok=True)
            self._cache = CacheManager(
                ttl=3600,
                max_size=10000,
                use_disk_cache=True,
                disk_cache_path=self.cache_dir / "cache",
            )
            await self._cache.initialize()

        # 初始化数据库
        if self.db_path:
            self.db_path.parent.mkdir(parents=True, exist_ok=True)
            self._database = CompressedDatabase(self.db_path)
            await self._database.initialize()

        self._initialized = True
        logger.info("MCP 服务器（三层缓存 + 智能降级）初始化完成")

    async def shutdown(self) -> None:
        """关闭服务器并释放资源."""
        if self._local_search:
            await self._local_search.close()
        if self._remote_search:
            await self._remote_search.close()
        if self._fallback_strategy:
            await self._fallback_strategy.close()
        if self._cache:
            await self._cache.close()
        if self._database:
            await self._database.close()

        self._initialized = False
        logger.info("MCP 服务器已关闭")

    async def search_local(
        self,
        pattern: str,
        path: str = ".",
        include: list[str] | None = None,
        exclude: list[str] | None = None,
        use_regex: bool = True,
        case_sensitive: bool = False,
        max_results: int = 100,
        context_lines: int = 2,
    ) -> list[dict[str, Any]]:
        """执行本地搜索.

        Args:
            pattern: 搜索模式
            path: 搜索路径
            include: 包含的文件模式
            exclude: 排除的文件模式
            use_regex: 是否使用正则表达式
            case_sensitive: 是否区分大小写
            max_results: 最大结果数
            context_lines: 上下文行数

        Returns:
            搜索结果列表（字典格式）
        """
        if not self._initialized:
            await self.initialize()

        if not self._local_search:
            raise RuntimeError("本地搜索未初始化")

        results = await self._local_search.search(
            pattern=pattern,
            path=path,
            include=include,
            exclude=exclude,
            use_regex=use_regex,
            case_sensitive=case_sensitive,
            max_results=max_results,
            context_lines=context_lines,
        )

        return [r.to_dict() for r in results]

    async def search_remote(
        self,
        pattern: str,
        repo: str,
        platform: str = "github",
        ref: str = "HEAD",
        path: str = "",
        language: str | None = None,
        max_results: int = 100,
    ) -> list[dict[str, Any]]:
        """执行远程搜索.

        Args:
            pattern: 搜索模式
            repo: 仓库标识
            platform: 平台名称
            ref: 分支/标签
            path: 路径过滤
            language: 语言过滤
            max_results: 最大结果数

        Returns:
            搜索结果列表（字典格式）
        """
        if not self._initialized:
            await self.initialize()

        if not self._remote_search:
            raise RuntimeError("远程搜索未初始化")

        results = await self._remote_search.search(
            pattern=pattern,
            repo=repo,
            platform=platform,
            ref=ref,
            path=path,
            language=language,
            max_results=max_results,
        )

        return [r.to_dict() for r in results]

    async def search_remote_three_layer(
        self,
        pattern: str,
        repo: str,
        platform: str = "github",
        ref: str = "HEAD",
        path: str = "",
        language: str | None = None,
        max_results: int = 100,
    ) -> dict[str, Any]:
        """执行三层缓存远程搜索.

        Args:
            pattern: 搜索模式
            repo: 仓库标识
            platform: 平台名称
            ref: 分支/标签
            path: 路径过滤
            language: 语言过滤
            max_results: 最大结果数

        Returns:
            包含结果和统计的字典
        """
        start_time = time.perf_counter()
        self._request_count += 1

        try:
            if not self._remote_search:
                raise RuntimeError("远程搜索未初始化")

            results, stats = await self._remote_search.search_with_three_layer_cache(
                pattern=pattern,
                repo=repo,
                platform=platform,
                ref=ref,
                path=path,
                language=language,
                max_results=max_results,
            )

            elapsed = (time.perf_counter() - start_time) * 1000
            self._total_response_time_ms += elapsed

            return {
                "results": [r.to_dict() for r in results],
                "stats": stats.to_dict(),
                "performance": {
                    "total_time_ms": round(elapsed, 2),
                    "l1_hit_rate": stats.l1_hit_rate,
                    "overall_hit_rate": stats.overall_hit_rate,
                },
            }

        except Exception as e:
            self._error_count += 1
            logger.exception(f"三层缓存搜索失败：{e}")
            raise

    async def search_with_fallback(
        self,
        pattern: str,
        repo: str,
        platform: str = "github",
        ref: str = "HEAD",
        path: str = "",
        language: str | None = None,
        max_results: int = 100,
        enable_fallback: bool = True,
    ) -> dict[str, Any]:
        """执行带智能降级的远程搜索.

        Args:
            pattern: 搜索模式
            repo: 仓库标识
            platform: 平台名称
            ref: 分支/标签
            path: 路径过滤
            language: 语言过滤
            max_results: 最大结果数
            enable_fallback: 是否启用降级

        Returns:
            包含结果和降级信息的字典
        """
        start_time = time.perf_counter()
        self._request_count += 1

        try:
            if not self._remote_search:
                raise RuntimeError("远程搜索未初始化")

            if not enable_fallback or not self._fallback_strategy:
                # 不使用降级，直接搜索
                result = await self.search_remote_three_layer(
                    pattern, repo, platform, ref, path, language, max_results
                )
                result["fallback_used"] = False
                return result

            # 使用降级策略执行搜索
            async def primary_search():
                results, _ = await self._remote_search.search_with_three_layer_cache(
                    pattern=pattern,
                    repo=repo,
                    platform=platform,
                    ref=ref,
                    path=path,
                    language=language,
                    max_results=max_results,
                )
                return results

            # 定义降级链
            fallback_funcs = []

            result = await self._fallback_strategy.execute_with_fallback(
                primary_search,
                fallback_chain=fallback_funcs,
                pathway_id=f"{platform}:{repo}",
            )

            elapsed = (time.perf_counter() - start_time) * 1000
            self._total_response_time_ms += elapsed

            return {
                "results": [r.to_dict() for r in result.result] if result.result else [],
                "fallback": result.to_dict(),
                "performance": {
                    "total_time_ms": round(elapsed, 2),
                },
            }

        except Exception as e:
            self._error_count += 1
            logger.exception(f"降级搜索失败：{e}")
            raise

    async def get_three_layer_stats(self) -> dict[str, Any]:
        """获取三层缓存统计.

        Returns:
            三层缓存统计数据
        """
        if not self._remote_search:
            return {"enabled": False}

        stats = self._remote_search.get_three_layer_stats()
        return {
            "enabled": True,
            **stats.to_dict(),
        }

    async def get_fallback_metrics(self) -> dict[str, Any]:
        """获取智能降级通路指标.

        Returns:
            降级通路指标
        """
        if not self._fallback_strategy:
            return {"enabled": False}

        return {
            "enabled": True,
            "metrics": self._fallback_strategy.get_all_metrics(),
            "healthy_pathways": self._fallback_strategy.get_healthy_pathways(),
            "best_pathway": self._fallback_strategy.get_best_pathway(),
            "performance_report": self._fallback_strategy.get_performance_report(),
        }

    async def health_check(self) -> dict[str, Any]:
        """健康检查端点.

        Returns:
            健康状态信息
        """
        uptime = time.time() - self._start_time
        avg_response_time = (
            self._total_response_time_ms / self._request_count
            if self._request_count > 0
            else 0
        )

        health_status = "healthy"
        issues = []

        # 检查组件状态
        if not self._local_search:
            issues.append("local_search not initialized")
        if not self._remote_search:
            issues.append("remote_search not initialized")
        if self.fallback_enabled and not self._fallback_strategy:
            issues.append("fallback_strategy not initialized")

        # 检查错误率
        error_rate = self._error_count / max(1, self._request_count)
        if error_rate > 0.5:
            health_status = "unhealthy"
            issues.append(f"high error rate: {error_rate:.2%}")
        elif error_rate > 0.2:
            health_status = "degraded"
            issues.append(f"elevated error rate: {error_rate:.2%}")

        # 检查三层缓存状态
        if self._remote_search:
            cache_stats = self._remote_search.get_three_layer_stats()
            if cache_stats.l1_hit_rate < 0.3 and cache_stats.l1_hits + cache_stats.l1_misses > 10:
                issues.append(f"low L1 cache hit rate: {cache_stats.l1_hit_rate:.2%}")

        return {
            "status": health_status,
            "uptime_seconds": round(uptime, 2),
            "request_count": self._request_count,
            "error_count": self._error_count,
            "error_rate": round(error_rate, 4),
            "avg_response_time_ms": round(avg_response_time, 2),
            "issues": issues,
            "components": {
                "local_search": self._local_search is not None,
                "remote_search": self._remote_search is not None,
                "fallback_strategy": self._fallback_strategy is not None if self.fallback_enabled else "disabled",
                "cache": self._cache is not None,
                "database": self._database is not None,
            },
            "timestamp": time.time(),
        }

    async def get_cache_stats(self) -> dict[str, Any]:
        """获取缓存统计.

        Returns:
            缓存统计数据
        """
        if not self._cache:
            return {"enabled": False}

        stats = self._cache.get_stats()
        return {
            "enabled": True,
            **stats.to_dict(),
        }

    async def clear_cache(self) -> dict[str, Any]:
        """清空缓存.

        Returns:
            操作结果
        """
        if not self._cache:
            return {"success": False, "message": "缓存未启用"}

        await self._cache.clear()
        return {"success": True, "message": "缓存已清空"}

    async def get_db_stats(self) -> dict[str, Any]:
        """获取数据库统计.

        Returns:
            数据库统计数据
        """
        if not self._database:
            return {"enabled": False}

        stats = await self._database.get_stats()
        return {
            "enabled": True,
            **stats.to_dict(),
        }


# 创建全局服务器实例
_server: GrepAppMCPServer | None = None


def get_server() -> GrepAppMCPServer:
    """获取服务器实例."""
    global _server
    if _server is None:
        # 从环境变量读取配置
        fallback_enabled = os.environ.get("GREP_APP_FALLBACK_ENABLED", "true").lower() == "true"

        _server = GrepAppMCPServer(
            cache_dir=os.environ.get("GREP_APP_CACHE_DIR"),
            db_path=os.environ.get("GREP_APP_DB_PATH"),
            git_cache_dir=os.environ.get("GREP_APP_GIT_CACHE_DIR"),
            github_token=os.environ.get("GITHUB_TOKEN"),
            max_workers=int(os.environ.get("GREP_APP_MAX_WORKERS", "4")),
            fallback_enabled=fallback_enabled,
        )
    return _server


def create_mcp_app() -> Server:
    """创建 MCP 应用.

    Returns:
        MCP 服务器实例
    """
    app = Server("grep-app-enhanced")

    @app.list_tools()
    async def list_tools() -> list[Tool]:
        """列出可用工具."""
        return [
            Tool(
                name="search_local",
                description="在本地文件系统中搜索代码",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "pattern": {
                            "type": "string",
                            "description": "搜索模式（支持正则表达式）",
                        },
                        "path": {
                            "type": "string",
                            "description": "搜索根路径",
                            "default": ".",
                        },
                        "include": {
                            "type": "array",
                            "items": {"type": "string"},
                            "description": "包含的文件模式列表",
                            "default": ["*"],
                        },
                        "exclude": {
                            "type": "array",
                            "items": {"type": "string"},
                            "description": "排除的文件模式列表",
                            "default": [".git", "__pycache__", "node_modules"],
                        },
                        "use_regex": {
                            "type": "boolean",
                            "description": "是否使用正则表达式",
                            "default": True,
                        },
                        "case_sensitive": {
                            "type": "boolean",
                            "description": "是否区分大小写",
                            "default": False,
                        },
                        "max_results": {
                            "type": "integer",
                            "description": "最大返回结果数",
                            "default": 100,
                        },
                        "context_lines": {
                            "type": "integer",
                            "description": "上下文行数",
                            "default": 2,
                        },
                    },
                    "required": ["pattern"],
                },
            ),
            Tool(
                name="search_remote",
                description="在远程 Git 仓库中搜索代码（传统方式）",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "pattern": {
                            "type": "string",
                            "description": "搜索模式",
                        },
                        "repo": {
                            "type": "string",
                            "description": "仓库标识 (owner/repo)",
                        },
                        "platform": {
                            "type": "string",
                            "description": "平台名称",
                            "enum": ["github", "gitlab", "gitee"],
                            "default": "github",
                        },
                        "ref": {
                            "type": "string",
                            "description": "分支/标签/提交",
                            "default": "HEAD",
                        },
                        "path": {
                            "type": "string",
                            "description": "路径过滤",
                            "default": "",
                        },
                        "language": {
                            "type": "string",
                            "description": "语言过滤",
                        },
                        "max_results": {
                            "type": "integer",
                            "description": "最大返回结果数",
                            "default": 100,
                        },
                    },
                    "required": ["pattern", "repo"],
                },
            ),
            Tool(
                name="search_remote_three_layer",
                description="在远程 Git 仓库中搜索代码（三层缓存增强版，L1 命中率>80%）",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "pattern": {
                            "type": "string",
                            "description": "搜索模式",
                        },
                        "repo": {
                            "type": "string",
                            "description": "仓库标识 (owner/repo)",
                        },
                        "platform": {
                            "type": "string",
                            "description": "平台名称",
                            "enum": ["github", "gitlab", "gitee"],
                            "default": "github",
                        },
                        "ref": {
                            "type": "string",
                            "description": "分支/标签/提交",
                            "default": "HEAD",
                        },
                        "path": {
                            "type": "string",
                            "description": "路径过滤",
                            "default": "",
                        },
                        "language": {
                            "type": "string",
                            "description": "语言过滤",
                        },
                        "max_results": {
                            "type": "integer",
                            "description": "最大返回结果数",
                            "default": 100,
                        },
                    },
                    "required": ["pattern", "repo"],
                },
            ),
            Tool(
                name="search_with_fallback",
                description="在远程 Git 仓库中搜索代码（带智能降级，延迟<100ms）",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "pattern": {
                            "type": "string",
                            "description": "搜索模式",
                        },
                        "repo": {
                            "type": "string",
                            "description": "仓库标识 (owner/repo)",
                        },
                        "platform": {
                            "type": "string",
                            "description": "平台名称",
                            "enum": ["github", "gitlab", "gitee"],
                            "default": "github",
                        },
                        "ref": {
                            "type": "string",
                            "description": "分支/标签/提交",
                            "default": "HEAD",
                        },
                        "path": {
                            "type": "string",
                            "description": "路径过滤",
                            "default": "",
                        },
                        "language": {
                            "type": "string",
                            "description": "语言过滤",
                        },
                        "max_results": {
                            "type": "integer",
                            "description": "最大返回结果数",
                            "default": 100,
                        },
                        "enable_fallback": {
                            "type": "boolean",
                            "description": "是否启用智能降级",
                            "default": True,
                        },
                    },
                    "required": ["pattern", "repo"],
                },
            ),
            Tool(
                name="get_three_layer_stats",
                description="获取三层缓存统计信息（L1/L2/L3 命中率）",
                inputSchema={
                    "type": "object",
                    "properties": {},
                },
            ),
            Tool(
                name="get_fallback_metrics",
                description="获取智能降级通路指标和健康状态",
                inputSchema={
                    "type": "object",
                    "properties": {},
                },
            ),
            Tool(
                name="health_check",
                description="健康检查端点（监控服务器状态）",
                inputSchema={
                    "type": "object",
                    "properties": {},
                },
            ),
            Tool(
                name="get_cache_stats",
                description="获取缓存统计信息",
                inputSchema={
                    "type": "object",
                    "properties": {},
                },
            ),
            Tool(
                name="clear_cache",
                description="清空缓存",
                inputSchema={
                    "type": "object",
                    "properties": {},
                },
            ),
            Tool(
                name="get_db_stats",
                description="获取数据库统计信息",
                inputSchema={
                    "type": "object",
                    "properties": {},
                },
            ),
        ]

    @app.call_tool()
    async def call_tool(name: str, arguments: dict[str, Any]) -> CallToolResult:
        """调用工具.

        Args:
            name: 工具名称
            arguments: 工具参数

        Returns:
            工具调用结果
        """
        server = get_server()

        try:
            if name == "search_local":
                results = await server.search_local(**arguments)
                content = TextContent(
                    type="text",
                    text=json.dumps(results, ensure_ascii=False, indent=2),
                )
            elif name == "search_remote":
                results = await server.search_remote(**arguments)
                content = TextContent(
                    type="text",
                    text=json.dumps(results, ensure_ascii=False, indent=2),
                )
            elif name == "search_remote_three_layer":
                result = await server.search_remote_three_layer(**arguments)
                content = TextContent(
                    type="text",
                    text=json.dumps(result, ensure_ascii=False, indent=2),
                )
            elif name == "search_with_fallback":
                result = await server.search_with_fallback(**arguments)
                content = TextContent(
                    type="text",
                    text=json.dumps(result, ensure_ascii=False, indent=2),
                )
            elif name == "get_three_layer_stats":
                stats = await server.get_three_layer_stats()
                content = TextContent(
                    type="text",
                    text=json.dumps(stats, ensure_ascii=False, indent=2),
                )
            elif name == "get_fallback_metrics":
                metrics = await server.get_fallback_metrics()
                content = TextContent(
                    type="text",
                    text=json.dumps(metrics, ensure_ascii=False, indent=2),
                )
            elif name == "health_check":
                health = await server.health_check()
                content = TextContent(
                    type="text",
                    text=json.dumps(health, ensure_ascii=False, indent=2),
                )
            elif name == "get_cache_stats":
                stats = await server.get_cache_stats()
                content = TextContent(
                    type="text",
                    text=json.dumps(stats, ensure_ascii=False, indent=2),
                )
            elif name == "clear_cache":
                result = await server.clear_cache()
                content = TextContent(
                    type="text",
                    text=json.dumps(result, ensure_ascii=False, indent=2),
                )
            elif name == "get_db_stats":
                stats = await server.get_db_stats()
                content = TextContent(
                    type="text",
                    text=json.dumps(stats, ensure_ascii=False, indent=2),
                )
            else:
                return CallToolResult(
                    isError=True,
                    content=[TextContent(type="text", text=f"未知工具：{name}")],
                )

            return CallToolResult(content=[content])

        except Exception as e:
            logger.exception(f"工具调用失败：{name}")
            return CallToolResult(
                isError=True,
                content=[TextContent(type="text", text=f"错误：{str(e)}")],
            )

    return app


@click.command()
@click.version_option(version=__version__)
@click.option(
    "--cache-dir",
    envvar="GREP_APP_CACHE_DIR",
    help="缓存目录路径",
)
@click.option(
    "--db-path",
    envvar="GREP_APP_DB_PATH",
    help="数据库文件路径",
)
@click.option(
    "--git-cache-dir",
    envvar="GREP_APP_GIT_CACHE_DIR",
    help="Git 仓库缓存目录（L2 缓存）",
)
@click.option(
    "--github-token",
    envvar="GITHUB_TOKEN",
    help="GitHub API Token",
)
@click.option(
    "--max-workers",
    envvar="GREP_APP_MAX_WORKERS",
    type=int,
    default=4,
    help="最大工作线程数",
)
@click.option(
    "--fallback-enabled",
    envvar="GREP_APP_FALLBACK_ENABLED",
    type=bool,
    default=True,
    help="启用智能降级",
)
@click.option(
    "--debug",
    is_flag=True,
    help="启用调试模式",
)
def main(
    cache_dir: str | None,
    db_path: str | None,
    git_cache_dir: str | None,
    github_token: str | None,
    max_workers: int,
    fallback_enabled: bool,
    debug: bool,
) -> None:
    """运行 grep-app-enhanced MCP 服务器.

    该服务器提供本地和远程代码搜索功能，
    支持三层缓存（L1 SQLite+ZSTD, L2 Git, L3 Remote）
    和智能降级策略.

    Example:
        ```bash
        # 基本运行
        grep-app-enhanced

        # 指定三层缓存
        grep-app-enhanced --db-path /tmp/grep.db --git-cache-dir /tmp/git-cache

        # 启用调试模式
        grep-app-enhanced --debug

        # 禁用智能降级
        grep-app-enhanced --fallback-enabled=false
        ```
    """
    if debug:
        logging.getLogger().setLevel(logging.DEBUG)

    # 创建并配置服务器
    global _server
    _server = GrepAppMCPServer(
        cache_dir=cache_dir,
        db_path=db_path,
        git_cache_dir=git_cache_dir,
        github_token=github_token,
        max_workers=max_workers,
        fallback_enabled=fallback_enabled,
    )

    # 创建 MCP 应用
    mcp_app = create_mcp_app()

    # 运行服务器
    async def run() -> None:
        await _server.initialize()
        try:
            async with stdio_server() as (read_stream, write_stream):
                await mcp_app.run(
                    read_stream,
                    write_stream,
                    mcp_app.create_initialization_options(),
                )
        finally:
            await _server.shutdown()

    try:
        asyncio.run(run())
    except KeyboardInterrupt:
        logger.info("服务器已停止")
    except Exception as e:
        logger.exception(f"服务器错误：{e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
