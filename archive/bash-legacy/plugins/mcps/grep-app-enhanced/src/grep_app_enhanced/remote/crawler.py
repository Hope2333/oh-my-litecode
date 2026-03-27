"""
Git Crawler - Git 仓库爬虫模块.

本模块提供通过 HTTP/HTTPS 爬取 Git 仓库内容的功能，支持：
- 直接文件获取
- 目录遍历
- 批量下载
- 内容搜索
- 多平台仓库搜索
- 速率限制与 robots.txt 遵守

Example:
    ```python
    from grep_app_enhanced.remote import GitCrawler

    crawler = GitCrawler()
    await crawler.initialize()

    # 获取单个文件
    content = await crawler.fetch_file(
        "https://github.com/owner/repo",
        "main",
        "src/main.py"
    )

    # 搜索仓库
    repos = await crawler.search_repositories("machine learning", platform="github")

    # 遍历目录
    files = await crawler.list_directory(
        "https://github.com/owner/repo",
        "main",
        "src/"
    )
    ```

Supported Platforms:
    - GitHub
    - GitLab
    - Gitee
    - 其他支持 raw 文件访问的 Git 平台

URL Formats:
    - GitHub: https://github.com/owner/repo
    - GitLab: https://gitlab.com/owner/repo
    - Gitee: https://gitee.com/owner/repo

Rate Limiting:
    - 默认：10 请求/秒
    - 可配置：通过 rate_limit 参数
    - 自动退避：遇到 429 时自动增加延迟

Robots.txt:
    - 自动检查并遵守 robots.txt 规则
    - 缓存 robots.txt 内容（TTL: 1 小时）
    - 可通过 respect_robots 参数禁用

Author:
    Oh My LiteCode Team
"""

from __future__ import annotations

import asyncio
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

import httpx
from bs4 import BeautifulSoup


@dataclass
class GitFile:
    """Git 文件数据类.

    Attributes:
        name: 文件名
        path: 完整路径
        type: 类型 (file/dir)
        size: 文件大小（字节）
        url: 原始内容 URL
        html_url: 网页 URL
        sha: Git SHA 哈希

    Example:
        ```python
        file = GitFile(
            name="main.py",
            path="src/main.py",
            type="file",
            size=1024
        )
        ```
    """

    name: str
    path: str
    type: str  # "file" or "dir"
    size: int = 0
    url: str = ""
    html_url: str = ""
    sha: str = ""

    @property
    def is_file(self) -> bool:
        """检查是否为文件."""
        return self.type == "file"

    @property
    def is_directory(self) -> bool:
        """检查是否为目录."""
        return self.type == "dir"


@dataclass
class RepoInfo:
    """仓库信息数据类.

    Attributes:
        owner: 仓库所有者
        repo: 仓库名
        platform: 平台名称 (github/gitlab/gitee)
        default_branch: 默认分支
        html_url: 网页 URL
        api_url: API URL
        raw_url: 原始内容 URL 模板

    Example:
        ```python
        info = RepoInfo(
            owner="microsoft",
            repo="vscode",
            platform="github",
            default_branch="main"
        )
        ```
    """

    owner: str
    repo: str
    platform: str
    default_branch: str = "main"
    html_url: str = ""
    api_url: str = ""
    raw_url: str = ""

    def build_raw_url(self, ref: str, path: str) -> str:
        """构建原始内容 URL.

        Args:
            ref: 分支/标签
            path: 文件路径

        Returns:
            原始内容 URL
        """
        if self.platform == "github":
            return f"https://raw.githubusercontent.com/{self.owner}/{self.repo}/{ref}/{path}"
        elif self.platform == "gitlab":
            return f"https://gitlab.com/{self.owner}/{self.repo}/-/raw/{ref}/{path}"
        elif self.platform == "gitee":
            return f"https://gitee.com/{self.owner}/{self.repo}/raw/{ref}/{path}"
        else:
            raise ValueError(f"不支持的平台：{self.platform}")


class GitCrawler:
    """Git 仓库爬虫类.

    提供通过 HTTP/HTTPS 爬取 Git 仓库内容的功能，
    支持多个 Git 托管平台.

    Attributes:
        timeout: 请求超时时间（秒）
        max_retries: 最大重试次数
        retry_delay: 重试延迟（秒）

    Example:
        ```python
        crawler = GitCrawler(timeout=30, max_retries=3)
        await crawler.initialize()

        content = await crawler.fetch_file(
            "https://github.com/owner/repo",
            "main",
            "README.md"
        )
        ```

    Note:
        - 优先使用平台 API（如果可用）
        - 回退到网页爬取（当 API 不可用时）
        - 自动处理速率限制
    """

    DEFAULT_TIMEOUT = 30
    DEFAULT_MAX_RETRIES = 3
    DEFAULT_RETRY_DELAY = 1.0

    PLATFORM_PATTERNS = {
        "github": re.compile(r"github\.com[:/]([^/]+)/([^/]+?)(?:\.git)?/?$"),
        "gitlab": re.compile(r"gitlab\.com[:/]([^/]+)/([^/]+?)(?:\.git)?/?$"),
        "gitee": re.compile(r"gitee\.com[:/]([^/]+)/([^/]+?)(?:\.git)?/?$"),
    }

    def __init__(
        self,
        timeout: int = DEFAULT_TIMEOUT,
        max_retries: int = DEFAULT_MAX_RETRIES,
        retry_delay: float = DEFAULT_RETRY_DELAY,
        token: str | None = None,
        rate_limit: float = 10.0,
        respect_robots: bool = True,
    ) -> None:
        """初始化 Git 爬虫.

        Args:
            timeout: 请求超时时间（秒）
            max_retries: 最大重试次数
            retry_delay: 重试延迟（秒）
            token: API Token (可选)
            rate_limit: 每秒请求数限制（默认 10）
            respect_robots: 是否遵守 robots.txt（默认 True）
        """
        self.timeout = timeout
        self.max_retries = max_retries
        self.retry_delay = retry_delay
        self.token = token
        self.rate_limit = rate_limit
        self.respect_robots = respect_robots

        self._client: httpx.AsyncClient | None = None
        self._robots_cache: dict[str, tuple[float, list[str]]] = {}  # {domain: (expiry, rules)}
        self._last_request_time: float = 0.0
        self._request_count: int = 0

    async def initialize(self) -> None:
        """初始化 HTTP 客户端."""
        headers = {
            "User-Agent": "grep-app-enhanced/0.1.0 GitCrawler",
        }
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"

        self._client = httpx.AsyncClient(
            timeout=self.timeout,
            headers=headers,
            follow_redirects=True,
        )

    async def close(self) -> None:
        """关闭客户端并释放资源."""
        if self._client:
            await self._client.aclose()
            self._client = None

    async def __aenter__(self) -> GitCrawler:
        """异步上下文管理器入口."""
        await self.initialize()
        return self

    async def __aexit__(self, exc_type: Any, exc_val: Any, exc_tb: Any) -> None:
        """异步上下文管理器出口."""
        await self.close()

    def parse_repo_url(self, url: str) -> RepoInfo:
        """解析仓库 URL.

        Args:
            url: 仓库 URL

        Returns:
            仓库信息

        Raises:
            ValueError: URL 格式无效或平台不支持
        """
        # 移除 .git 后缀和尾部斜杠
        url = url.rstrip("/").removesuffix(".git")

        for platform, pattern in self.PLATFORM_PATTERNS.items():
            match = pattern.search(url)
            if match:
                owner, repo = match.groups()
                return RepoInfo(
                    owner=owner,
                    repo=repo,
                    platform=platform,
                    html_url=url,
                )

        raise ValueError(f"不支持的仓库 URL: {url}")

    async def _request_with_retry(
        self,
        method: str,
        url: str,
        **kwargs: Any,
    ) -> httpx.Response:
        """带重试的请求.

        Args:
            method: HTTP 方法
            url: 请求 URL
            **kwargs: 传递给 httpx 的参数

        Returns:
            HTTP 响应

        Raises:
            httpx.HTTPError: 所有重试都失败
        """
        if not self._client:
            raise RuntimeError("客户端未初始化")

        last_error: Exception | None = None

        for attempt in range(self.max_retries):
            try:
                response = await self._client.request(method, url, **kwargs)

                # 处理速率限制
                if response.status_code == 429:
                    retry_after = float(response.headers.get("Retry-After", self.retry_delay))
                    await asyncio.sleep(retry_after)
                    continue

                response.raise_for_status()
                return response

            except httpx.HTTPError as e:
                last_error = e
                if attempt < self.max_retries - 1:
                    await asyncio.sleep(self.retry_delay * (attempt + 1))

        if last_error:
            raise last_error
        raise RuntimeError("请求失败")

    async def fetch_file(
        self,
        repo_url: str,
        ref: str = "main",
        path: str = "",
    ) -> str:
        """获取文件内容.

        Args:
            repo_url: 仓库 URL
            ref: 分支/标签/提交
            path: 文件路径

        Returns:
            文件内容

        Raises:
            ValueError: 解析 URL 失败
            httpx.HTTPError: 获取文件失败
        """
        repo_info = self.parse_repo_url(repo_url)
        raw_url = repo_info.build_raw_url(ref, path)

        response = await self._request_with_retry("GET", raw_url)
        return response.text

    async def fetch_file_bytes(
        self,
        repo_url: str,
        ref: str = "main",
        path: str = "",
    ) -> bytes:
        """获取文件原始字节.

        Args:
            repo_url: 仓库 URL
            ref: 分支/标签/提交
            path: 文件路径

        Returns:
            文件字节内容
        """
        repo_info = self.parse_repo_url(repo_url)
        raw_url = repo_info.build_raw_url(ref, path)

        response = await self._request_with_retry("GET", raw_url)
        return response.content

    async def list_directory(
        self,
        repo_url: str,
        ref: str = "main",
        path: str = "",
    ) -> list[GitFile]:
        """列出目录内容.

        Args:
            repo_url: 仓库 URL
            ref: 分支/标签/提交
            path: 目录路径

        Returns:
            文件/目录列表

        Raises:
            ValueError: 解析 URL 失败
        """
        repo_info = self.parse_repo_url(repo_url)

        if repo_info.platform == "github":
            return await self._list_github_directory(repo_info, ref, path)
        elif repo_info.platform == "gitlab":
            return await self._list_gitlab_directory(repo_info, ref, path)
        else:
            # 回退到网页爬取
            return await self._crawl_directory_html(repo_info, ref, path)

    async def _list_github_directory(
        self,
        repo_info: RepoInfo,
        ref: str,
        path: str,
    ) -> list[GitFile]:
        """列出 GitHub 目录内容."""
        api_url = (
            f"https://api.github.com/repos/{repo_info.owner}/{repo_info.repo}"
            f"/contents/{path}"
        )
        params = {"ref": ref}

        headers = {}
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"

        response = await self._request_with_retry(
            "GET",
            api_url,
            params=params,
            headers=headers,
        )

        data = response.json()
        return [
            GitFile(
                name=item["name"],
                path=item["path"],
                type="dir" if item["type"] == "dir" else "file",
                size=item.get("size", 0),
                url=item.get("download_url", ""),
                html_url=item.get("html_url", ""),
                sha=item.get("sha", ""),
            )
            for item in data
        ]

    async def _list_gitlab_directory(
        self,
        repo_info: RepoInfo,
        ref: str,
        path: str,
    ) -> list[GitFile]:
        """列出 GitLab 目录内容."""
        # GitLab API 需要 URL 编码的项目路径
        project_path = f"{repo_info.owner}/{repo_info.repo}"
        api_url = (
            f"https://gitlab.com/api/v4/projects/{urlencode(project_path)}/repository/tree"
        )
        params = {
            "ref": ref,
            "path": path,
            "per_page": 100,
        }

        headers = {}
        if self.token:
            headers["PRIVATE-TOKEN"] = self.token

        response = await self._request_with_retry(
            "GET",
            api_url,
            params=params,
            headers=headers,
        )

        data = response.json()
        return [
            GitFile(
                name=item["name"],
                path=item["path"],
                type="dir" if item["type"] == "tree" else "file",
                url="",
                html_url=f"{repo_info.html_url}/-/blob/{ref}/{item['path']}",
            )
            for item in data
        ]

    async def _crawl_directory_html(
        self,
        repo_info: RepoInfo,
        ref: str,
        path: str,
    ) -> list[GitFile]:
        """通过 HTML 爬取目录内容（回退方案）."""
        if not self._client:
            raise RuntimeError("客户端未初始化")

        url = f"{repo_info.html_url}/tree/{ref}/{path}"
        response = await self._request_with_retry("GET", url)

        soup = BeautifulSoup(response.text, "html.parser")
        files = []

        # 查找文件列表（GitHub 结构）
        for row in soup.select(".js-navigation-item"):
            link = row.select_one(".js-navigation-open")
            if not link:
                continue

            name = link.get_text(strip=True)
            href = link.get("href", "")

            # 判断类型
            svg_icon = row.select_one("svg")
            file_type = "dir" if svg_icon and "directory" in svg_icon.get("class", []) else "file"

            files.append(
                GitFile(
                    name=name,
                    path=f"{path}/{name}".lstrip("/"),
                    type=file_type,
                    html_url=f"https://github.com{href}" if href.startswith("/") else href,
                )
            )

        return files

    async def search_in_repo(
        self,
        repo_url: str,
        pattern: str,
        ref: str = "main",
        path: str = "",
        extensions: list[str] | None = None,
    ) -> list[GitFile]:
        """在仓库中搜索文件.

        Args:
            repo_url: 仓库 URL
            pattern: 搜索模式
            ref: 分支/标签/提交
            path: 搜索路径
            extensions: 文件扩展名过滤

        Returns:
            匹配的文件列表
        """
        repo_info = self.parse_repo_url(repo_url)
        files = await self.list_directory(repo_url, ref, path)

        results = []
        for file in files:
            if file.is_file:
                # 检查扩展名
                if extensions:
                    file_ext = Path(file.name).suffix.lstrip(".")
                    if file_ext not in extensions:
                        continue

                # 检查模式匹配
                import re

                if re.search(pattern, file.name, re.IGNORECASE):
                    results.append(file)

        return results

    async def download_file(
        self,
        repo_url: str,
        ref: str = "main",
        path: str = "",
        dest_path: str | Path | None = None,
    ) -> Path:
        """下载文件到本地.

        Args:
            repo_url: 仓库 URL
            ref: 分支/标签/提交
            path: 文件路径
            dest_path: 目标路径（默认为当前目录）

        Returns:
            保存的文件路径
        """
        content = await self.fetch_file_bytes(repo_url, ref, path)

        if dest_path is None:
            dest_path = Path.cwd() / Path(path).name
        else:
            dest_path = Path(dest_path)

        dest_path.parent.mkdir(parents=True, exist_ok=True)
        dest_path.write_bytes(content)

        return dest_path


def urlencode(s: str) -> str:
    """简单的 URL 编码."""
    import urllib.parse

    return urllib.parse.quote(s, safe="")


# =========================================================================
# 新增：多平台搜索与速率限制功能
# =========================================================================

@dataclass
class RepositorySearchResult:
    """仓库搜索结果数据类.

    Attributes:
        owner: 仓库所有者
        repo: 仓库名
        platform: 平台名称
        description: 仓库描述
        html_url: 网页 URL
        clone_url: Git 克隆 URL
        stars: Star 数量
        forks: Fork 数量
        language: 主要语言
        updated_at: 最后更新时间

    Example:
        ```python
        result = RepositorySearchResult(
            owner="microsoft",
            repo="vscode",
            platform="github",
            description="Code editor",
            stars=150000
        )
        ```
    """

    owner: str
    repo: str
    platform: str
    description: str = ""
    html_url: str = ""
    clone_url: str = ""
    stars: int = 0
    forks: int = 0
    language: str = ""
    updated_at: str = ""

    @property
    def full_name(self) -> str:
        """获取完整仓库名."""
        return f"{self.owner}/{self.repo}"


class RobotsParser:
    """robots.txt 解析器.

    提供 robots.txt 规则的解析和检查功能.

    Example:
        ```python
        parser = RobotsParser()
        await parser.fetch("https://github.com")
        if parser.can_fetch("https://github.com/owner/repo"):
            # 可以爬取
            pass
        ```
    """

    DEFAULT_TTL = 3600  # 1 小时缓存

    def __init__(self, user_agent: str = "grep-app-enhanced") -> None:
        """初始化 robots 解析器.

        Args:
            user_agent: User-Agent 标识
        """
        self.user_agent = user_agent
        self._rules: dict[str, list[tuple[bool, str]]] = {}  # {path: [(allow, pattern)]}
        self._fetched_at: float = 0.0
        self._raw_content: str = ""

    async def fetch(self, base_url: str, client: httpx.AsyncClient) -> bool:
        """获取并解析 robots.txt.

        Args:
            base_url: 基础 URL
            client: HTTP 客户端

        Returns:
            是否成功获取
        """
        from urllib.parse import urlparse

        parsed = urlparse(base_url)
        robots_url = f"{parsed.scheme}://{parsed.netloc}/robots.txt"

        try:
            response = await client.get(robots_url, timeout=10.0)
            if response.status_code == 200:
                self._raw_content = response.text
                self._parse(self._raw_content)
                self._fetched_at = asyncio.get_event_loop().time()
                return True
        except Exception:
            pass

        return False

    def _parse(self, content: str) -> None:
        """解析 robots.txt 内容.

        Args:
            content: robots.txt 内容
        """
        self._rules.clear()
        current_agents: list[str] = []
        current_rules: list[tuple[bool, str]] = []

        for line in content.splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue

            if ":" in line:
                key, value = line.split(":", 1)
                key = key.strip().lower()
                value = value.strip()

                if key == "user-agent":
                    if current_agents and current_rules:
                        # 保存之前的规则
                        for agent in current_agents:
                            if agent not in self._rules:
                                self._rules[agent] = []
                            self._rules[agent].extend(current_rules)

                    current_agents = [value.lower()]
                    current_rules = []

                elif key in ("allow", "disallow") and current_agents:
                    allow = key == "allow"
                    if value:
                        current_rules.append((allow, value))

        # 保存最后一组规则
        if current_agents and current_rules:
            for agent in current_agents:
                if agent not in self._rules:
                    self._rules[agent] = []
                self._rules[agent].extend(current_rules)

        # 添加通用规则（*）
        if "*" not in self._rules and current_rules:
            self._rules["*"] = current_rules

    def can_fetch(self, url: str) -> bool:
        """检查是否可以爬取 URL.

        Args:
            url: 要检查的 URL

        Returns:
            如果可以爬取返回 True
        """
        from urllib.parse import urlparse

        parsed = urlparse(url)
        path = parsed.path

        # 获取适用的规则
        rules = self._rules.get(self.user_agent.lower(), self._rules.get("*", []))

        if not rules:
            return True  # 没有规则限制

        # 按规则长度排序，更具体的规则优先
        sorted_rules = sorted(rules, key=lambda x: len(x[1]), reverse=True)

        allowed = True
        for allow, pattern in sorted_rules:
            if self._match_pattern(path, pattern):
                allowed = allow
                break  # 找到第一个匹配的规则

        return allowed

    def _match_pattern(self, path: str, pattern: str) -> bool:
        """检查路径是否匹配模式.

        Args:
            path: URL 路径
            pattern: robots.txt 模式

        Returns:
            是否匹配
        """
        # robots.txt 模式匹配规则
        # * 匹配任意序列，$ 匹配行尾
        if pattern.endswith("$"):
            # $ 表示精确匹配到路径结尾
            pattern = pattern[:-1]
            return path == pattern
        return path.startswith(pattern)

    def is_expired(self) -> bool:
        """检查缓存是否过期.

        Returns:
            是否过期
        """
        import time
        return time.time() - self._fetched_at > self.DEFAULT_TTL


class RateLimiter:
    """速率限制器.

    实现令牌桶算法，控制请求频率.

    Example:
        ```python
        limiter = RateLimiter(rate=10.0)  # 10 请求/秒
        await limiter.acquire()  # 等待获取令牌
        # 发送请求
        ```
    """

    def __init__(
        self,
        rate: float = 10.0,
        burst: int = 20,
    ) -> None:
        """初始化速率限制器.

        Args:
            rate: 每秒请求数
            burst: 突发容量
        """
        self.rate = rate
        self.burst = burst
        self._tokens = float(burst)
        self._last_update = asyncio.get_event_loop().time()
        self._lock = asyncio.Lock()

    async def acquire(self) -> None:
        """获取令牌（可能等待）."""
        async with self._lock:
            now = asyncio.get_event_loop().time()
            elapsed = now - self._last_update
            self._tokens = min(self.burst, self._tokens + elapsed * self.rate)
            self._last_update = now

            if self._tokens < 1:
                wait_time = (1 - self._tokens) / self.rate
                await asyncio.sleep(wait_time)
                self._tokens = 0
            else:
                self._tokens -= 1

    def reset(self) -> None:
        """重置限制器."""
        self._tokens = float(self.burst)
        self._last_update = asyncio.get_event_loop().time()


# =========================================================================
# 为 GitCrawler 添加新方法
# =========================================================================

async def _rate_limit_wait(self: GitCrawler) -> None:
    """等待速率限制.

    使用令牌桶算法控制请求频率.
    """
    import time

    now = time.time()
    min_interval = 1.0 / self.rate_limit if self.rate_limit > 0 else 0

    if self._last_request_time > 0:
        elapsed = now - self._last_request_time
        if elapsed < min_interval:
            await asyncio.sleep(min_interval - elapsed)

    self._last_request_time = time.time()
    self._request_count += 1


async def _check_robots_txt(self: GitCrawler, url: str) -> bool:
    """检查 robots.txt 是否允许爬取.

    Args:
        url: 要检查的 URL

    Returns:
        是否允许爬取
    """
    if not self.respect_robots:
        return True

    if not self._client:
        return True

    from urllib.parse import urlparse

    parsed = urlparse(url)
    domain = f"{parsed.scheme}://{parsed.netloc}"

    # 检查缓存
    cache_entry = self._robots_cache.get(domain)
    if cache_entry:
        expiry, rules = cache_entry
        import time
        if time.time() < expiry:
            # 简单的路径检查
            path = parsed.path
            for rule in rules:
                if path.startswith(rule):
                    return False
            return True

    # 获取 robots.txt
    try:
        robots_url = f"{domain}/robots.txt"
        response = await self._client.get(robots_url, timeout=5.0)
        if response.status_code == 200:
            rules = self._parse_robots_txt(response.text)
            import time
            self._robots_cache[domain] = (time.time() + 3600, rules)

            # 检查路径
            path = parsed.path
            for rule in rules:
                if path.startswith(rule):
                    return False
            return True
    except Exception:
        pass

    return True  # 获取失败时默认允许


def _parse_robots_txt(self: GitCrawler, content: str) -> list[str]:
    """解析 robots.txt 内容.

    Args:
        content: robots.txt 内容

    Returns:
        Disallow 规则列表
    """
    rules = []
    in_user_agent = False
    target_agents = ["*", "grep-app-enhanced"]

    for line in content.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue

        if ":" in line:
            key, value = line.split(":", 1)
            key = key.strip().lower()
            value = value.strip()

            if key == "user-agent":
                in_user_agent = value.lower() in target_agents
            elif key == "disallow" and in_user_agent and value:
                rules.append(value)
            elif key == "allow" and in_user_agent and value:
                # Allow 规则优先，这里简化处理
                pass

    return rules


#  monkey-patch 方法到 GitCrawler
GitCrawler._rate_limit_wait = _rate_limit_wait  # type: ignore
GitCrawler._check_robots_txt = _check_robots_txt  # type: ignore
GitCrawler._parse_robots_txt = _parse_robots_txt  # type: ignore


async def search_repositories(
    self: GitCrawler,
    query: str,
    platform: str = "github",
    language: str | None = None,
    min_stars: int = 0,
    max_results: int = 30,
    page: int = 1,
) -> list[RepositorySearchResult]:
    """搜索仓库（多平台支持）.

    Args:
        query: 搜索查询
        platform: 平台名称 (github/gitlab/gitee)
        language: 编程语言过滤
        min_stars: 最小 Star 数
        max_results: 最大结果数
        page: 页码

    Returns:
        仓库搜索结果列表

    Example:
        ```python
        crawler = GitCrawler()
        await crawler.initialize()

        repos = await crawler.search_repositories(
            "machine learning",
            platform="github",
            language="Python",
            min_stars=100
        )
        ```
    """
    await self._rate_limit_wait()

    if platform == "github":
        return await self._search_github(query, language, min_stars, max_results, page)
    elif platform == "gitlab":
        return await self._search_gitlab(query, language, min_stars, max_results, page)
    elif platform == "gitee":
        return await self._search_gitee(query, language, min_stars, max_results, page)
    else:
        raise ValueError(f"不支持的平台：{platform}")


async def _search_github(
    self: GitCrawler,
    query: str,
    language: str | None,
    min_stars: int,
    max_results: int,
    page: int,
) -> list[RepositorySearchResult]:
    """搜索 GitHub 仓库."""
    if not self._client:
        raise RuntimeError("客户端未初始化")

    q = query
    if language:
        q += f" language:{language}"
    if min_stars > 0:
        q += f" stars:>={min_stars}"

    headers = {}
    if self.token:
        headers["Authorization"] = f"Bearer {self.token}"

    url = "https://api.github.com/search/repositories"
    params = {
        "q": q,
        "sort": "stars",
        "order": "desc",
        "per_page": min(max_results, 100),
        "page": page,
    }

    response = await self._client.get(url, params=params, headers=headers)
    response.raise_for_status()
    data = response.json()

    results = []
    for item in data.get("items", []):
        results.append(RepositorySearchResult(
            owner=item["owner"]["login"],
            repo=item["name"],
            platform="github",
            description=item.get("description") or "",
            html_url=item.get("html_url") or "",
            clone_url=item.get("clone_url") or "",
            stars=item.get("stargazers_count") or 0,
            forks=item.get("forks_count") or 0,
            language=item.get("language") or "",
            updated_at=item.get("updated_at") or "",
        ))

    return results


async def _search_gitlab(
    self: GitCrawler,
    query: str,
    language: str | None,
    min_stars: int,
    max_results: int,
    page: int,
) -> list[RepositorySearchResult]:
    """搜索 GitLab 仓库."""
    if not self._client:
        raise RuntimeError("客户端未初始化")

    headers = {}
    if self.token:
        headers["PRIVATE-TOKEN"] = self.token

    url = "https://gitlab.com/api/v4/projects"
    params = {
        "search": query,
        "per_page": min(max_results, 100),
        "page": page,
        "order_by": "popularity",
        "sort": "desc",
    }

    response = await self._client.get(url, params=params, headers=headers)
    response.raise_for_status()
    data = response.json()

    results = []
    for item in data:
        # GitLab 不直接提供 star 数，使用 bookmark_count 替代
        results.append(RepositorySearchResult(
            owner=item["namespace"]["path"] if isinstance(item.get("namespace"), dict) else "",
            repo=item["name"],
            platform="gitlab",
            description=item.get("description") or "",
            html_url=item.get("web_url") or "",
            clone_url=item.get("http_url_to_repo") or "",
            stars=item.get("star_count") or 0,
            forks=item.get("forks_count") or 0,
            language="",  # GitLab API 不直接返回语言
            updated_at=item.get("last_activity_at") or "",
        ))

    return results


async def _search_gitee(
    self: GitCrawler,
    query: str,
    language: str | None,
    min_stars: int,
    max_results: int,
    page: int,
) -> list[RepositorySearchResult]:
    """搜索 Gitee 仓库."""
    if not self._client:
        raise RuntimeError("客户端未初始化")

    headers = {}
    if self.token:
        headers["Authorization"] = f"Bearer {self.token}"

    url = "https://gitee.com/api/v5/search/repositories"
    params = {
        "q": query,
        "language": language,
        "page": page,
        "per_page": min(max_results, 100),
        "sort": "stars_count",
        "order": "desc",
    }

    response = await self._client.get(url, params=params, headers=headers)
    response.raise_for_status()
    data = response.json()

    results = []
    for item in data:
        results.append(RepositorySearchResult(
            owner=item["owner"]["login"] if isinstance(item.get("owner"), dict) else "",
            repo=item["name"],
            platform="gitee",
            description=item.get("description") or "",
            html_url=item.get("html_url") or "",
            clone_url=item.get("clone_url") or "",
            stars=item.get("stargazers_count") or 0,
            forks=item.get("forks_count") or 0,
            language=item.get("language") or "",
            updated_at=item.get("updated_at") or "",
        ))

    return results


async def parse_search_results(
    self: GitCrawler,
    html: str,
    platform: str = "github",
) -> list[RepositorySearchResult]:
    """解析搜索结果的 HTML.

    Args:
        html: HTML 内容
        platform: 平台名称

    Returns:
        解析后的结果列表
    """
    from bs4 import BeautifulSoup

    soup = BeautifulSoup(html, "html.parser")
    results = []

    if platform == "github":
        # GitHub 搜索结果结构
        for item in soup.select(".repo-list-item"):
            name_elem = item.select_one(".v-align-text-top .text-bold")
            if not name_elem:
                continue

            full_name = name_elem.get_text(strip=True)
            parts = full_name.split("/")
            if len(parts) != 2:
                continue

            desc_elem = item.select_one(".mb-1 .col-12")
            lang_elem = item.select_one("[itemprop=programmingLanguage]")
            star_elem = item.select_one(".m-0 .octicon-star")

            results.append(RepositorySearchResult(
                owner=parts[0],
                repo=parts[1],
                platform="github",
                description=desc_elem.get_text(strip=True) if desc_elem else "",
                html_url=name_elem.get("href", "") if name_elem.get("href") else "",
                language=lang_elem.get_text(strip=True) if lang_elem else "",
            ))

    return results


# 将新方法绑定到 GitCrawler
GitCrawler.search_repositories = search_repositories  # type: ignore
GitCrawler.parse_search_results = parse_search_results  # type: ignore
GitCrawler._search_github = _search_github  # type: ignore
GitCrawler._search_gitlab = _search_gitlab  # type: ignore
GitCrawler._search_gitee = _search_gitee  # type: ignore


# 更新 _request_with_retry 方法以包含速率限制
async def _request_with_retry_enhanced(
    self: GitCrawler,
    method: str,
    url: str,
    **kwargs: Any,
) -> httpx.Response:
    """带重试和速率限制的请求（增强版）.

    Args:
        method: HTTP 方法
        url: 请求 URL
        **kwargs: 传递给 httpx 的参数

    Returns:
        HTTP 响应

    Raises:
        httpx.HTTPError: 所有重试都失败
    """
    if not self._client:
        raise RuntimeError("客户端未初始化")

    # 检查 robots.txt
    if not await self._check_robots_txt(url):
        raise PermissionError(f"robots.txt 禁止访问：{url}")

    # 速率限制
    await self._rate_limit_wait()

    last_error: Exception | None = None

    for attempt in range(self.max_retries):
        try:
            response = await self._client.request(method, url, **kwargs)

            # 处理速率限制
            if response.status_code == 429:
                retry_after = float(response.headers.get("Retry-After", self.retry_delay * (attempt + 1)))
                await asyncio.sleep(retry_after)
                continue

            response.raise_for_status()
            return response

        except httpx.HTTPError as e:
            last_error = e
            if attempt < self.max_retries - 1:
                await asyncio.sleep(self.retry_delay * (attempt + 1))

    if last_error:
        raise last_error
    raise RuntimeError("请求失败")


# 替换原有的 _request_with_retry 方法
GitCrawler._request_with_retry = _request_with_retry_enhanced  # type: ignore
