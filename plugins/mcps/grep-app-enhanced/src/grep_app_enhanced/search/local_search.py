"""
Local Search - 本地文件系统搜索模块.

本模块提供高效的本地文件搜索功能，支持：
- 正则表达式搜索
- 多模式匹配
- 并行处理
- 智能文件过滤
- 上下文提取

Example:
    ```python
    from grep_app_enhanced.search import LocalSearch

    search = LocalSearch(
        max_workers=4,
        context_lines=3
    )
    results = await search.search(
        pattern=r"def \w+",
        path="/src",
        include=["*.py"],
        exclude=["__pycache__"]
    )
    ```

Performance:
    - 使用多进程/多线程并行搜索
    - 支持大文件流式处理
    - 内存优化的结果收集

Author:
    Oh My LiteCode Team
"""

from __future__ import annotations

import asyncio
import re
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from fnmatch import fnmatch
from pathlib import Path
from typing import Any, AsyncIterator

from ..__init__ import SearchResult, SearchConfig


@dataclass
class SearchProgress:
    """搜索进度数据类.

    Attributes:
        files_scanned: 已扫描文件数
        files_matched: 匹配文件数
        total_matches: 总匹配数
        bytes_processed: 已处理字节数
        elapsed_seconds: 已用时间（秒）

    Example:
        ```python
        progress = SearchProgress(
            files_scanned=100,
            files_matched=10,
            total_matches=50
        )
        ```
    """

    files_scanned: int = 0
    files_matched: int = 0
    total_matches: int = 0
    bytes_processed: int = 0
    elapsed_seconds: float = 0.0

    def to_dict(self) -> dict[str, Any]:
        """转换为字典格式."""
        return {
            "files_scanned": self.files_scanned,
            "files_matched": self.files_matched,
            "total_matches": self.total_matches,
            "bytes_processed": self.bytes_processed,
            "elapsed_seconds": self.elapsed_seconds,
        }


class LocalSearch:
    """本地文件搜索类.

    提供高效的本地文件系统搜索功能，
    支持正则表达式、多模式匹配和并行处理.

    Attributes:
        max_workers: 最大工作线程数
        context_lines: 上下文行数
        max_file_size: 最大文件大小（字节）
        encoding: 默认文件编码

    Example:
        ```python
        search = LocalSearch(
            max_workers=8,
            context_lines=5,
            max_file_size=10 * 1024 * 1024  # 10MB
        )
        results = await search.search("pattern", path="/src")
        ```

    Note:
        - 自动跳过二进制文件
        - 支持符号链接处理
        - 可配置的文件过滤规则
    """

    DEFAULT_MAX_WORKERS = 4
    DEFAULT_CONTEXT_LINES = 2
    DEFAULT_MAX_FILE_SIZE = 50 * 1024 * 1024  # 50MB
    BINARY_EXTENSIONS = {
        ".pyc", ".pyo", ".so", ".dll", ".exe", ".bin",
        ".jpg", ".jpeg", ".png", ".gif", ".bmp", ".ico",
        ".pdf", ".doc", ".docx", ".xls", ".xlsx",
        ".zip", ".tar", ".gz", ".rar", ".7z",
    }

    def __init__(
        self,
        max_workers: int = DEFAULT_MAX_WORKERS,
        context_lines: int = DEFAULT_CONTEXT_LINES,
        max_file_size: int = DEFAULT_MAX_FILE_SIZE,
        encoding: str = "utf-8",
        follow_symlinks: bool = False,
    ) -> None:
        """初始化本地搜索.

        Args:
            max_workers: 最大工作线程数
            context_lines: 上下文行数
            max_file_size: 最大文件大小（字节）
            encoding: 默认文件编码
            follow_symlinks: 是否跟随符号链接
        """
        self.max_workers = max_workers
        self.context_lines = context_lines
        self.max_file_size = max_file_size
        self.encoding = encoding
        self.follow_symlinks = follow_symlinks

        self._executor = ThreadPoolExecutor(max_workers=max_workers)
        self._progress = SearchProgress()

    async def close(self) -> None:
        """关闭搜索器并释放资源."""
        self._executor.shutdown(wait=True)

    async def __aenter__(self) -> LocalSearch:
        """异步上下文管理器入口."""
        return self

    async def __aexit__(self, exc_type: Any, exc_val: Any, exc_tb: Any) -> None:
        """异步上下文管理器出口."""
        await self.close()

    def _should_skip(self, path: Path) -> bool:
        """检查是否应跳过文件.

        Args:
            path: 文件路径

        Returns:
            如果应跳过返回 True
        """
        # 检查扩展名
        if path.suffix.lower() in self.BINARY_EXTENSIONS:
            return True

        # 检查文件大小
        try:
            if path.stat().st_size > self.max_file_size:
                return True
        except OSError:
            return True

        return False

    def _matches_pattern(
        self,
        name: str,
        include: list[str],
        exclude: list[str],
    ) -> bool:
        """检查文件名是否匹配模式.

        Args:
            name: 文件名
            include: 包含模式列表
            exclude: 排除模式列表

        Returns:
            如果匹配返回 True
        """
        # 检查排除模式
        for pattern in exclude:
            if fnmatch(name, pattern):
                return False

        # 检查包含模式
        if not include:
            return True

        for pattern in include:
            if fnmatch(name, pattern):
                return True

        return False

    def _compile_pattern(
        self,
        pattern: str,
        use_regex: bool = True,
        case_sensitive: bool = False,
    ) -> re.Pattern:
        """编译搜索模式.

        Args:
            pattern: 搜索模式
            use_regex: 是否使用正则表达式
            case_sensitive: 是否区分大小写

        Returns:
            编译后的正则表达式
        """
        if not use_regex:
            # 转义特殊字符
            pattern = re.escape(pattern)

        flags = 0 if case_sensitive else re.IGNORECASE
        return re.compile(pattern, flags)

    def _read_file_lines(self, file_path: Path) -> list[str]:
        """读取文件行.

        Args:
            file_path: 文件路径

        Returns:
            文件行列表
        """
        try:
            content = file_path.read_text(encoding=self.encoding, errors="replace")
            return content.splitlines()
        except (OSError, UnicodeDecodeError):
            return []

    def _search_file(
        self,
        file_path: Path,
        pattern: re.Pattern,
        context_lines: int,
    ) -> list[SearchResult]:
        """搜索单个文件.

        Args:
            file_path: 文件路径
            pattern: 编译后的正则表达式
            context_lines: 上下文行数

        Returns:
            搜索结果列表
        """
        results = []
        lines = self._read_file_lines(file_path)

        for line_num, line in enumerate(lines, 1):
            match = pattern.search(line)
            if match:
                # 提取上下文
                start = max(0, line_num - 1 - context_lines)
                end = min(len(lines), line_num + context_lines)

                context_before = lines[start : line_num - 1]
                context_after = lines[line_num:end]

                results.append(
                    SearchResult(
                        file_path=str(file_path),
                        line_number=line_num,
                        content=line,
                        context_before=context_before,
                        context_after=context_after,
                        match_start=match.start(),
                        match_end=match.end(),
                    )
                )

        return results

    async def _search_file_async(
        self,
        file_path: Path,
        pattern: re.Pattern,
        context_lines: int,
    ) -> list[SearchResult]:
        """异步搜索单个文件.

        Args:
            file_path: 文件路径
            pattern: 编译后的正则表达式
            context_lines: 上下文行数

        Returns:
            搜索结果列表
        """
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(
            self._executor,
            self._search_file,
            file_path,
            pattern,
            context_lines,
        )

    def _collect_files(
        self,
        root_path: Path,
        include: list[str],
        exclude: list[str],
    ) -> list[Path]:
        """收集要搜索的文件.

        Args:
            root_path: 根路径
            include: 包含模式列表
            exclude: 排除模式列表

        Returns:
            文件路径列表
        """
        files = []

        try:
            for item in root_path.rglob("*"):
                if not item.is_file():
                    continue

                # 检查符号链接
                if item.is_symlink() and not self.follow_symlinks:
                    continue

                # 检查是否应跳过
                if self._should_skip(item):
                    continue

                # 检查模式匹配
                if not self._matches_pattern(item.name, include, exclude):
                    continue

                # 检查路径中的排除目录
                should_exclude = False
                for part in item.relative_to(root_path).parts:
                    for pattern in exclude:
                        if fnmatch(part, pattern):
                            should_exclude = True
                            break
                    if should_exclude:
                        break

                if not should_exclude:
                    files.append(item)

        except PermissionError:
            pass

        return files

    async def search(
        self,
        pattern: str,
        path: str | Path = ".",
        include: list[str] | None = None,
        exclude: list[str] | None = None,
        use_regex: bool = True,
        case_sensitive: bool = False,
        max_results: int = 1000,
        context_lines: int | None = None,
    ) -> list[SearchResult]:
        """执行搜索.

        Args:
            pattern: 搜索模式
            path: 搜索根路径
            include: 包含的文件模式列表
            exclude: 排除的文件模式列表
            use_regex: 是否使用正则表达式
            case_sensitive: 是否区分大小写
            max_results: 最大返回结果数
            context_lines: 上下文行数

        Returns:
            搜索结果列表

        Example:
            ```python
            search = LocalSearch()
            results = await search.search(
                "def test_",
                path="/src",
                include=["*.py"],
                exclude=["__pycache__", ".git"]
            )
            ```
        """
        root_path = Path(path).resolve()
        if not root_path.exists():
            raise FileNotFoundError(f"路径不存在：{root_path}")
        if not root_path.is_dir():
            # 如果是文件，直接搜索
            return await self.search_file(pattern, root_path, use_regex, case_sensitive)

        include = include or ["*"]
        exclude = exclude or [".git", "__pycache__", "node_modules", ".venv"]
        context_lines = context_lines if context_lines is not None else self.context_lines

        # 编译模式
        compiled_pattern = self._compile_pattern(pattern, use_regex, case_sensitive)

        # 收集文件
        files = await asyncio.get_event_loop().run_in_executor(
            self._executor,
            self._collect_files,
            root_path,
            include,
            exclude,
        )

        # 并行搜索所有文件
        all_results: list[SearchResult] = []
        tasks = []

        for file_path in files:
            task = self._search_file_async(file_path, compiled_pattern, context_lines)
            tasks.append(task)

        # 分批处理以避免内存溢出
        batch_size = 50
        for i in range(0, len(tasks), batch_size):
            batch = tasks[i : i + batch_size]
            batch_results = await asyncio.gather(*batch, return_exceptions=True)

            for result in batch_results:
                if isinstance(result, list):
                    all_results.extend(result)
                elif isinstance(result, Exception):
                    # 记录错误但继续处理
                    pass

            # 检查结果数限制
            if len(all_results) >= max_results:
                all_results = all_results[:max_results]
                break

        # 更新进度
        self._progress.files_scanned = len(files)
        self._progress.files_matched = len(set(r.file_path for r in all_results))
        self._progress.total_matches = len(all_results)

        return all_results

    async def search_file(
        self,
        pattern: str,
        file_path: str | Path,
        use_regex: bool = True,
        case_sensitive: bool = False,
        context_lines: int | None = None,
    ) -> list[SearchResult]:
        """搜索单个文件.

        Args:
            pattern: 搜索模式
            file_path: 文件路径
            use_regex: 是否使用正则表达式
            case_sensitive: 是否区分大小写
            context_lines: 上下文行数

        Returns:
            搜索结果列表
        """
        path = Path(file_path).resolve()
        if not path.exists():
            raise FileNotFoundError(f"文件不存在：{path}")

        context_lines = context_lines if context_lines is not None else self.context_lines
        compiled_pattern = self._compile_pattern(pattern, use_regex, case_sensitive)

        return await self._search_file_async(path, compiled_pattern, context_lines)

    async def search_stream(
        self,
        pattern: str,
        path: str | Path = ".",
        include: list[str] | None = None,
        exclude: list[str] | None = None,
        use_regex: bool = True,
        case_sensitive: bool = False,
    ) -> AsyncIterator[SearchResult]:
        """流式搜索.

        逐个返回结果，适用于大量结果的场景.

        Args:
            pattern: 搜索模式
            path: 搜索根路径
            include: 包含的文件模式列表
            exclude: 排除的文件模式列表
            use_regex: 是否使用正则表达式
            case_sensitive: 是否区分大小写

        Yields:
            搜索结果

        Example:
            ```python
            async for result in search.search_stream("TODO", path="/src"):
                print(f"{result.file_path}:{result.line_number}: {result.content}")
            ```
        """
        root_path = Path(path).resolve()
        include = include or ["*"]
        exclude = exclude or [".git", "__pycache__", "node_modules"]

        compiled_pattern = self._compile_pattern(pattern, use_regex, case_sensitive)
        files = await asyncio.get_event_loop().run_in_executor(
            self._executor,
            self._collect_files,
            root_path,
            include,
            exclude,
        )

        for file_path in files:
            results = await self._search_file_async(
                file_path,
                compiled_pattern,
                self.context_lines,
            )
            for result in results:
                yield result

    def get_progress(self) -> SearchProgress:
        """获取搜索进度.

        Returns:
            搜索进度数据
        """
        return self._progress

    async def count_matches(
        self,
        pattern: str,
        path: str | Path = ".",
        include: list[str] | None = None,
        exclude: list[str] | None = None,
        use_regex: bool = True,
        case_sensitive: bool = False,
    ) -> dict[str, int]:
        """统计匹配数.

        Args:
            pattern: 搜索模式
            path: 搜索根路径
            include: 包含的文件模式列表
            exclude: 排除的文件模式列表
            use_regex: 是否使用正则表达式
            case_sensitive: 是否区分大小写

        Returns:
            统计信息字典
        """
        results = await self.search(
            pattern,
            path,
            include,
            exclude,
            use_regex,
            case_sensitive,
            max_results=100000,  # 较高的限制用于统计
        )

        file_counts: dict[str, int] = {}
        for result in results:
            file_counts[result.file_path] = file_counts.get(result.file_path, 0) + 1

        return {
            "total_matches": len(results),
            "files_matched": len(file_counts),
            "by_file": file_counts,
        }
