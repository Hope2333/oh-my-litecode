"""
Grep App Enhanced - 增强版代码搜索 MCP 服务器.

本模块提供增强版的代码搜索功能，支持：
- ZSTD 压缩数据库，减少存储空间占用
- 智能缓存管理，提升搜索性能
- 远程仓库搜索（GitHub/GitLab 等）
- 本地文件系统搜索
- MCP 协议集成

Example:
    ```python
    from grep_app_enhanced import GrepAppEnhanced

    app = GrepAppEnhanced()
    results = await app.search("pattern", path="/path/to/code")
    ```

Version:
    0.1.0

Author:
    Oh My LiteCode Team
"""

from __future__ import annotations

__version__ = "0.1.0"
__author__ = "Oh My LiteCode Team"
__email__ = "team@oh-my-litecode.dev"
__all__ = [
    "__version__",
    "__author__",
    "__email__",
    "GrepAppEnhanced",
    "SearchResult",
    "SearchConfig",
]

from dataclasses import dataclass, field
from typing import Any


@dataclass
class SearchResult:
    """搜索结果数据类.

    Attributes:
        file_path: 匹配文件的路径
        line_number: 匹配行号
        content: 匹配行内容
        context_before: 上下文（前 N 行）
        context_after: 上下文（后 N 行）
        match_start: 匹配起始位置
        match_end: 匹配结束位置
        metadata: 额外元数据

    Example:
        ```python
        result = SearchResult(
            file_path="/path/to/file.py",
            line_number=42,
            content="def search(pattern):",
            match_start=4,
            match_end=10
        )
        ```
    """

    file_path: str
    line_number: int
    content: str
    context_before: list[str] = field(default_factory=list)
    context_after: list[str] = field(default_factory=list)
    match_start: int | None = None
    match_end: int | None = None
    metadata: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        """转换为字典格式.

        Returns:
            包含所有字段的字典
        """
        return {
            "file_path": self.file_path,
            "line_number": self.line_number,
            "content": self.content,
            "context_before": self.context_before,
            "context_after": self.context_after,
            "match_start": self.match_start,
            "match_end": self.match_end,
            "metadata": self.metadata,
        }


@dataclass
class SearchConfig:
    """搜索配置数据类.

    Attributes:
        pattern: 搜索模式（支持正则表达式）
        path: 搜索根路径
        include: 包含的文件模式列表
        exclude: 排除的文件模式列表
        max_results: 最大返回结果数
        context_lines: 上下文行数
        use_regex: 是否使用正则表达式
        case_sensitive: 是否区分大小写
        use_cache: 是否使用缓存
        cache_ttl: 缓存生存时间（秒）

    Example:
        ```python
        config = SearchConfig(
            pattern="def test_",
            path="/path/to/tests",
            include=["*.py"],
            exclude=["__pycache__"],
            max_results=100
        )
        ```
    """

    pattern: str
    path: str = "."
    include: list[str] = field(default_factory=lambda: ["*"])
    exclude: list[str] = field(default_factory=lambda: [".git", "__pycache__", "node_modules"])
    max_results: int = 1000
    context_lines: int = 2
    use_regex: bool = True
    case_sensitive: bool = False
    use_cache: bool = True
    cache_ttl: int = 3600


class GrepAppEnhanced:
    """增强版 Grep 应用主类.

    提供统一的搜索接口，整合本地搜索、远程搜索和缓存管理功能.

    Attributes:
        config: 默认搜索配置
        cache_enabled: 是否启用缓存

    Example:
        ```python
        from grep_app_enhanced import GrepAppEnhanced, SearchConfig

        app = GrepAppEnhanced()
        config = SearchConfig(pattern="TODO", include=["*.py"])
        results = await app.search_with_config(config)
        ```
    """

    def __init__(self, config: SearchConfig | None = None) -> None:
        """初始化 GrepAppEnhanced.

        Args:
            config: 可选的默认搜索配置
        """
        self.config = config or SearchConfig(pattern="")
        self.cache_enabled = True
        self._database = None
        self._cache_manager = None

    async def search(self, pattern: str, path: str = ".", **kwargs: Any) -> list[SearchResult]:
        """执行搜索.

        Args:
            pattern: 搜索模式
            path: 搜索路径
            **kwargs: 额外配置参数

        Returns:
            搜索结果列表

        Raises:
            FileNotFoundError: 路径不存在
            PermissionError: 无访问权限
        """
        config = SearchConfig(pattern=pattern, path=path, **kwargs)
        return await self.search_with_config(config)

    async def search_with_config(self, config: SearchConfig) -> list[SearchResult]:
        """使用配置执行搜索.

        Args:
            config: 搜索配置

        Returns:
            搜索结果列表

        Note:
            此方法为占位实现，实际功能由各子模块提供
        """
        # 占位实现 - 实际由 search 模块处理
        return []

    async def close(self) -> None:
        """关闭应用并释放资源.

        清理数据库连接、缓存等资源.
        """
        if self._database:
            await self._database.close()
        if self._cache_manager:
            await self._cache_manager.clear()

    async def __aenter__(self) -> GrepAppEnhanced:
        """异步上下文管理器入口."""
        return self

    async def __aexit__(self, exc_type: Any, exc_val: Any, exc_tb: Any) -> None:
        """异步上下文管理器出口."""
        await self.close()
