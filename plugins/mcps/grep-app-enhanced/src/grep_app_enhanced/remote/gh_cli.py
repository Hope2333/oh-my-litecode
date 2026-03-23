"""
GitHub CLI - GitHub 命令行接口封装.

本模块提供对 GitHub CLI (gh) 工具的封装，支持：
- 仓库搜索
- 代码搜索
- Issue/PR 搜索
- 文件内容获取
- 仓库克隆

Example:
    ```python
    from grep_app_enhanced.remote import GitHubCLI

    gh = GitHubCLI(token="ghp_xxx")
    repos = await gh.search_repos("machine learning", language="Python")

    code_results = await gh.search_code(
        "def main",
        owner="microsoft",
        repo="vscode"
    )
    ```

Requirements:
    - GitHub CLI (gh) 已安装并配置
    - 或者提供有效的 GitHub Token

Authentication:
    支持两种认证方式：
    1. 系统已配置的 gh CLI (通过 gh auth login)
    2. 直接提供 GitHub Token

Rate Limits:
    - 未认证：60 请求/小时
    - 已认证：5000 请求/小时
    - 代码搜索：10 请求/分钟 (已认证)

Author:
    Oh My LiteCode Team
"""

from __future__ import annotations

import asyncio
import json
import shutil
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import httpx


@dataclass
class GitHubRepo:
    """GitHub 仓库数据类.

    Attributes:
        full_name: 完整仓库名 (owner/repo)
        description: 仓库描述
        html_url: 网页 URL
        clone_url: Git 克隆 URL
        stargazers_count: Star 数量
        forks_count: Fork 数量
        language: 主要语言
        updated_at: 最后更新时间
        topics: 标签列表

    Example:
        ```python
        repo = GitHubRepo(
            full_name="owner/repo",
            description="A sample project",
            html_url="https://github.com/owner/repo"
        )
        ```
    """

    full_name: str
    description: str | None = None
    html_url: str = ""
    clone_url: str = ""
    stargazers_count: int = 0
    forks_count: int = 0
    language: str | None = None
    updated_at: str = ""
    topics: list[str] = field(default_factory=list)

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> GitHubRepo:
        """从字典创建实例.

        Args:
            data: GitHub API 返回的字典

        Returns:
            GitHubRepo 实例
        """
        return cls(
            full_name=data.get("full_name", ""),
            description=data.get("description"),
            html_url=data.get("html_url", ""),
            clone_url=data.get("clone_url", ""),
            stargazers_count=data.get("stargazers_count", 0),
            forks_count=data.get("forks_count", 0),
            language=data.get("language"),
            updated_at=data.get("updated_at", ""),
            topics=data.get("topics", []),
        )


@dataclass
class CodeSearchResult:
    """代码搜索结果数据类.

    Attributes:
        name: 文件名
        path: 文件路径
        repository: 所属仓库
        url: 文件 URL
        content: 文件内容（可选）
        matches: 匹配的行列表

    Example:
        ```python
        result = CodeSearchResult(
            name="main.py",
            path="src/main.py",
            repository="owner/repo",
            url="https://github.com/..."
        )
        ```
    """

    name: str
    path: str
    repository: str
    url: str
    content: str | None = None
    matches: list[dict[str, Any]] = field(default_factory=list)

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> CodeSearchResult:
        """从字典创建实例.

        Args:
            data: GitHub API 返回的字典

        Returns:
            CodeSearchResult 实例
        """
        repo = data.get("repository", {})
        return cls(
            name=data.get("name", ""),
            path=data.get("path", ""),
            repository=repo.get("full_name", "") if repo else "",
            url=data.get("html_url", ""),
            matches=data.get("text_matches", []),
        )


class GitHubCLI:
    """GitHub CLI 封装类.

    提供对 GitHub CLI 工具和 GitHub API 的封装，
    支持仓库搜索、代码搜索等功能.

    Attributes:
        token: GitHub Token (可选)
        api_base: GitHub API 基础 URL
        timeout: 请求超时时间（秒）

    Example:
        ```python
        gh = GitHubCLI(token="ghp_xxx")
        await gh.initialize()

        repos = await gh.search_repos("python")
        code = await gh.search_code("def test_")
        ```

    Note:
        - 优先使用 gh CLI 工具（如果已安装）
        - 如果 gh 不可用，则使用 HTTP API
        - Token 可以通过参数提供或使用环境变量
    """

    API_BASE = "https://api.github.com"
    DEFAULT_TIMEOUT = 30

    def __init__(
        self,
        token: str | None = None,
        api_base: str | None = None,
        timeout: int = DEFAULT_TIMEOUT,
    ) -> None:
        """初始化 GitHub CLI.

        Args:
            token: GitHub Token (可选，如果 gh CLI 已认证可不提供)
            api_base: GitHub API 基础 URL (用于 GitHub Enterprise)
            timeout: 请求超时时间（秒）
        """
        self.token = token
        self.api_base = api_base or self.API_BASE
        self.timeout = timeout

        self._gh_available: bool | None = None
        self._client: httpx.AsyncClient | None = None

    async def initialize(self) -> None:
        """初始化客户端.

        检查 gh CLI 可用性并创建 HTTP 客户端.
        """
        self._gh_available = self._check_gh_available()
        self._client = httpx.AsyncClient(
            base_url=self.api_base,
            timeout=self.timeout,
            headers=self._get_headers(),
        )

    async def close(self) -> None:
        """关闭客户端并释放资源."""
        if self._client:
            await self._client.aclose()
            self._client = None

    async def __aenter__(self) -> GitHubCLI:
        """异步上下文管理器入口."""
        await self.initialize()
        return self

    async def __aexit__(self, exc_type: Any, exc_val: Any, exc_tb: Any) -> None:
        """异步上下文管理器出口."""
        await self.close()

    def _check_gh_available(self) -> bool:
        """检查 gh CLI 是否可用.

        Returns:
            如果 gh CLI 可用返回 True
        """
        return shutil.which("gh") is not None

    def _get_headers(self) -> dict[str, str]:
        """获取请求头.

        Returns:
            包含认证信息的请求头
        """
        headers = {
            "Accept": "application/vnd.github.v3+json",
            "User-Agent": "grep-app-enhanced/0.1.0",
        }

        token = self.token
        if not token and self._gh_available:
            # 尝试从 gh 获取 token
            try:
                result = asyncio.get_event_loop().run_until_complete(
                    self._run_gh_command(["auth", "token"])
                )
                token = result.strip()
            except Exception:
                pass

        if token:
            headers["Authorization"] = f"Bearer {token}"

        return headers

    async def _run_gh_command(self, args: list[str]) -> str:
        """运行 gh CLI 命令.

        Args:
            args: 命令参数列表

        Returns:
            命令输出

        Raises:
            RuntimeError: gh CLI 不可用或命令失败
        """
        if not self._gh_available:
            raise RuntimeError("gh CLI 不可用")

        cmd = ["gh"] + args
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await process.communicate()

        if process.returncode != 0:
            raise RuntimeError(f"gh 命令失败：{stderr.decode()}")

        return stdout.decode()

    async def _api_request(
        self,
        method: str,
        endpoint: str,
        params: dict[str, Any] | None = None,
        data: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """发送 API 请求.

        Args:
            method: HTTP 方法
            endpoint: API 端点
            params: 查询参数
            data: 请求体数据

        Returns:
            API 响应数据

        Raises:
            httpx.HTTPError: 请求失败
        """
        if not self._client:
            raise RuntimeError("客户端未初始化")

        response = await self._client.request(
            method=method,
            url=endpoint,
            params=params,
            json=data,
        )
        response.raise_for_status()
        return response.json()

    async def search_repos(
        self,
        query: str,
        language: str | None = None,
        sort: str = "stars",
        order: str = "desc",
        per_page: int = 30,
        page: int = 1,
    ) -> list[GitHubRepo]:
        """搜索 GitHub 仓库.

        Args:
            query: 搜索查询
            language: 编程语言过滤
            sort: 排序字段 (stars, forks, help-issues, updated)
            order: 排序顺序 (asc, desc)
            per_page: 每页结果数
            page: 页码

        Returns:
            仓库列表

        Example:
            ```python
            repos = await gh.search_repos(
                "machine learning",
                language="Python",
                per_page=10
            )
            ```
        """
        q = query
        if language:
            q += f" language:{language}"

        params = {
            "q": q,
            "sort": sort,
            "order": order,
            "per_page": min(per_page, 100),
            "page": page,
        }

        data = await self._api_request("GET", "/search/repositories", params=params)
        return [GitHubRepo.from_dict(item) for item in data.get("items", [])]

    async def search_code(
        self,
        query: str,
        owner: str | None = None,
        repo: str | None = None,
        language: str | None = None,
        path: str | None = None,
        extension: str | None = None,
        per_page: int = 30,
        page: int = 1,
    ) -> list[CodeSearchResult]:
        """搜索 GitHub 代码.

        Args:
            query: 搜索查询
            owner: 仓库所有者过滤
            repo: 仓库名过滤
            language: 编程语言过滤
            path: 文件路径过滤
            extension: 文件扩展名过滤
            per_page: 每页结果数
            page: 页码

        Returns:
            代码搜索结果列表

        Example:
            ```python
            results = await gh.search_code(
                "def main",
                owner="microsoft",
                language="Python"
            )
            ```

        Note:
            代码搜索需要认证才能使用
        """
        q = query
        if owner and repo:
            q += f" repo:{owner}/{repo}"
        elif owner:
            q += f" user:{owner}"
        if language:
            q += f" language:{language}"
        if path:
            q += f" path:{path}"
        if extension:
            q += f" extension:{extension}"

        params = {
            "q": q,
            "per_page": min(per_page, 100),
            "page": page,
        }

        data = await self._api_request("GET", "/search/code", params=params)
        return [CodeSearchResult.from_dict(item) for item in data.get("items", [])]

    async def get_file_content(
        self,
        owner: str,
        repo: str,
        path: str,
        ref: str = "main",
    ) -> str:
        """获取文件内容.

        Args:
            owner: 仓库所有者
            repo: 仓库名
            path: 文件路径
            ref: 分支/标签/提交哈希

        Returns:
            文件内容

        Raises:
            httpx.HTTPError: 文件不存在或请求失败
        """
        endpoint = f"/repos/{owner}/{repo}/contents/{path}"
        params = {"ref": ref}

        data = await self._api_request("GET", endpoint, params=params)

        # GitHub API 返回 base64 编码的内容
        import base64

        content = data.get("content", "")
        encoding = data.get("encoding", "")

        if encoding == "base64":
            return base64.b64decode(content).decode("utf-8")
        return content

    async def clone_repo(
        self,
        full_name: str,
        dest_path: str | Path,
        branch: str | None = None,
        depth: int | None = None,
    ) -> None:
        """克隆仓库.

        Args:
            full_name: 完整仓库名 (owner/repo)
            dest_path: 目标路径
            branch: 分支名
            depth: 浅克隆深度

        Raises:
            RuntimeError: git 命令失败
        """
        clone_url = f"https://github.com/{full_name}.git"

        cmd = ["git", "clone"]
        if branch:
            cmd.extend(["-b", branch])
        if depth:
            cmd.extend(["--depth", str(depth)])
        cmd.extend([clone_url, str(dest_path)])

        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        _, stderr = await process.communicate()

        if process.returncode != 0:
            raise RuntimeError(f"git clone 失败：{stderr.decode()}")

    async def get_user_info(self) -> dict[str, Any]:
        """获取当前用户信息.

        Returns:
            用户信息字典

        Raises:
            httpx.HTTPError: 请求失败
        """
        return await self._api_request("GET", "/user")

    async def list_user_repos(
        self,
        username: str | None = None,
        per_page: int = 30,
        page: int = 1,
    ) -> list[GitHubRepo]:
        """列出用户仓库.

        Args:
            username: 用户名（None 表示当前用户）
            per_page: 每页结果数
            page: 页码

        Returns:
            仓库列表
        """
        if username:
            endpoint = f"/users/{username}/repos"
        else:
            endpoint = "/user/repos"

        params = {
            "per_page": min(per_page, 100),
            "page": page,
        }

        data = await self._api_request("GET", endpoint, params=params)
        return [GitHubRepo.from_dict(item) for item in data]

    # =========================================================================
    # 远程通路增强方法
    # =========================================================================

    async def gh_search_code(
        self,
        query: str,
        owner: str | None = None,
        repo: str | None = None,
        language: str | None = None,
        path: str | None = None,
        extension: str | None = None,
        per_page: int = 30,
        page: int = 1,
        use_gh_cli: bool = True,
    ) -> list[CodeSearchResult]:
        """搜索 GitHub 代码（增强版，支持 gh CLI 和 API 双通路）.

        Args:
            query: 搜索查询
            owner: 仓库所有者过滤
            repo: 仓库名过滤
            language: 编程语言过滤
            path: 文件路径过滤
            extension: 文件扩展名过滤
            per_page: 每页结果数
            page: 页码
            use_gh_cli: 是否优先使用 gh CLI

        Returns:
            代码搜索结果列表

        Example:
            ```python
            gh = GitHubCLI(token="ghp_xxx")
            await gh.initialize()

            results = await gh.gh_search_code(
                "def main",
                language="Python",
                per_page=10
            )
            ```

        Note:
            - 优先使用 gh CLI（如果已安装且认证）
            - 回退到 GitHub API
            - 代码搜索有速率限制
        """
        # 尝试使用 gh CLI
        if use_gh_cli and self._gh_available:
            try:
                return await self._gh_search_code_cli(
                    query, owner, repo, language, path, extension, per_page, page
                )
            except Exception:
                # CLI 失败，回退到 API
                pass

        # 使用 API
        return await self.search_code(
            query=query,
            owner=owner,
            repo=repo,
            language=language,
            path=path,
            extension=extension,
            per_page=per_page,
            page=page,
        )

    async def _gh_search_code_cli(
        self,
        query: str,
        owner: str | None = None,
        repo: str | None = None,
        language: str | None = None,
        path: str | None = None,
        extension: str | None = None,
        per_page: int = 30,
        page: int = 1,
    ) -> list[CodeSearchResult]:
        """使用 gh CLI 搜索代码.

        Args:
            query: 搜索查询
            owner: 仓库所有者
            repo: 仓库名
            language: 语言
            path: 路径
            extension: 扩展名
            per_page: 每页结果数
            page: 页码

        Returns:
            搜索结果列表
        """
        # 构建搜索查询
        q = query
        if owner and repo:
            q += f" repo:{owner}/{repo}"
        elif owner:
            q += f" user:{owner}"
        if language:
            q += f" language:{language}"
        if path:
            q += f" path:{path}"
        if extension:
            q += f" extension:{extension}"

        # gh search code 命令
        args = [
            "search", "code",
            q,
            "--limit", str(per_page),
            "--json", "name,path,repository,html_url,textMatches",
        ]

        output = await self._run_gh_command(args)

        if not output.strip():
            return []

        import json as json_module
        data = json_module.loads(output)

        results = []
        for item in data:
            results.append(CodeSearchResult.from_dict({
                "name": item.get("name", ""),
                "path": item.get("path", ""),
                "repository": item.get("repository", {}),
                "html_url": item.get("html_url", ""),
                "text_matches": item.get("textMatches", []),
            }))

        return results

    async def gh_get_file(
        self,
        owner: str,
        repo: str,
        path: str,
        ref: str = "main",
        use_gh_cli: bool = True,
    ) -> str:
        """获取文件内容（增强版，支持 gh CLI 和 API 双通路）.

        Args:
            owner: 仓库所有者
            repo: 仓库名
            path: 文件路径
            ref: 分支/标签/提交哈希
            use_gh_cli: 是否优先使用 gh CLI

        Returns:
            文件内容

        Raises:
            httpx.HTTPError: 文件不存在或请求失败
            RuntimeError: gh CLI 失败

        Example:
            ```python
            gh = GitHubCLI()
            await gh.initialize()

            content = await gh.gh_get_file(
                "microsoft", "vscode",
                "README.md"
            )
            ```
        """
        # 尝试使用 gh CLI
        if use_gh_cli and self._gh_available:
            try:
                return await self._gh_get_file_cli(owner, repo, path, ref)
            except Exception:
                # CLI 失败，回退到 API
                pass

        # 使用 API
        return await self.get_file_content(owner, repo, path, ref)

    async def _gh_get_file_cli(
        self,
        owner: str,
        repo: str,
        path: str,
        ref: str = "main",
    ) -> str:
        """使用 gh CLI 获取文件内容.

        Args:
            owner: 仓库所有者
            repo: 仓库名
            path: 文件路径
            ref: 引用

        Returns:
            文件内容
        """
        # 使用 gh api 获取文件
        endpoint = f"/repos/{owner}/{repo}/contents/{path}"
        args = ["api", endpoint, "-q", ".content"]

        if ref:
            args.extend(["-f", f"ref={ref}"])

        output = await self._run_gh_command(args)

        # 解码 base64
        import base64
        content = output.strip()

        if content:
            try:
                return base64.b64decode(content).decode("utf-8")
            except Exception:
                return content

        return ""

    async def gh_auth_check(self) -> dict[str, Any]:
        """检查 GitHub 认证状态.

        Returns:
            认证状态字典，包含：
            - authenticated: 是否已认证
            - method: 认证方式 (cli/token/none)
            - user: 用户名（如果已认证）
            - token_scopes: Token 权限范围
            - rate_limit: 速率限制信息
            - gh_available: gh CLI 是否可用

        Example:
            ```python
            gh = GitHubCLI()
            await gh.initialize()

            status = await gh.gh_auth_check()
            if status["authenticated"]:
                print(f"已认证为用户：{status['user']}")
            ```
        """
        result = {
            "authenticated": False,
            "method": "none",
            "user": None,
            "token_scopes": [],
            "rate_limit": {"remaining": 60, "limit": 60},
            "gh_available": self._gh_available,
        }

        # 检查 gh CLI 认证
        if self._gh_available:
            try:
                # 检查 gh auth status
                output = await self._run_gh_command(["auth", "status"])
                if "Logged in to" in output:
                    result["authenticated"] = True
                    result["method"] = "cli"

                    # 尝试获取用户名
                    try:
                        user_output = await self._run_gh_command(["api", "user", "-q", ".login"])
                        result["user"] = user_output.strip()
                    except Exception:
                        pass

                    # 获取速率限制
                    try:
                        rate_output = await self._run_gh_command([
                            "api", "/rate_limit", "-q", ".resources.core"
                        ])
                        import json as json_module
                        rate_data = json_module.loads(rate_output)
                        result["rate_limit"] = {
                            "remaining": rate_data.get("remaining", 60),
                            "limit": rate_data.get("limit", 5000),
                        }
                    except Exception:
                        pass

                return result

            except Exception:
                pass

        # 检查 Token 认证
        if self.token:
            result["method"] = "token"
            try:
                # 使用 API 验证 token
                user_data = await self.get_user_info()
                result["authenticated"] = True
                result["user"] = user_data.get("login")

                # 获取速率限制
                headers = self._get_headers()
                if self._client:
                    response = await self._client.get("/rate_limit", headers=headers)
                    if response.status_code == 200:
                        rate_data = response.json()
                        result["rate_limit"] = {
                            "remaining": rate_data.get("resources", {}).get("core", {}).get("remaining", 5000),
                            "limit": rate_data.get("resources", {}).get("core", {}).get("limit", 5000),
                        }
            except Exception:
                pass

        return result

    async def fallback_detection(self) -> dict[str, Any]:
        """检测可用通路并返回降级策略.

        Returns:
            通路状态字典，包含：
            - primary: 推荐的主通路 (gh_cli/api/http)
            - available_methods: 可用方法列表
            - rate_limit_status: 速率限制状态
            - recommendations: 使用建议

        Example:
            ```python
            gh = GitHubCLI()
            await gh.initialize()

            status = await gh.fallback_detection()
            print(f"推荐通路：{status['primary']}")
            ```
        """
        available_methods = []
        recommendations = []

        # 检查 gh CLI
        gh_cli_available = False
        gh_cli_authenticated = False
        if self._gh_available:
            gh_cli_available = True
            available_methods.append("gh_cli")
            try:
                auth_status = await self.gh_auth_check()
                if auth_status.get("authenticated"):
                    gh_cli_authenticated = True
                    recommendations.append("gh CLI 已认证，推荐使用")
            except Exception:
                pass

        # 检查 API
        api_available = bool(self.token)
        if api_available:
            available_methods.append("api")
            try:
                auth_status = await self.gh_auth_check()
                if auth_status.get("authenticated"):
                    remaining = auth_status.get("rate_limit", {}).get("remaining", 0)
                    if remaining < 100:
                        recommendations.append(f"API 速率限制紧张（剩余 {remaining}）")
                    else:
                        recommendations.append("API 可用")
            except Exception:
                pass

        # 检查 HTTP 回退（无需认证）
        http_available = True
        available_methods.append("http")
        recommendations.append("HTTP 回退模式可用（功能受限）")

        # 确定主通路
        primary = "none"
        if gh_cli_authenticated:
            primary = "gh_cli"
        elif api_available:
            primary = "api"
        elif http_available:
            primary = "http"

        return {
            "primary": primary,
            "available_methods": available_methods,
            "gh_cli_available": gh_cli_available,
            "gh_cli_authenticated": gh_cli_authenticated,
            "api_available": api_available,
            "rate_limit_status": "ok" if "紧张" not in str(recommendations) else "limited",
            "recommendations": recommendations,
        }

    async def search_with_fallback(
        self,
        query: str,
        owner: str | None = None,
        repo: str | None = None,
        **kwargs: Any,
    ) -> list[CodeSearchResult]:
        """带降级策略的代码搜索.

        Args:
            query: 搜索查询
            owner: 仓库所有者
            repo: 仓库名
            **kwargs: 其他参数

        Returns:
            搜索结果列表

        Note:
            自动检测可用通路并降级
        """
        # 检测通路
        status = await self.fallback_detection()

        if status["primary"] == "gh_cli":
            try:
                return await self.gh_search_code(query, owner, repo, **kwargs)
            except Exception:
                pass

        if status["primary"] in ("api", "gh_cli") or "api" in status["available_methods"]:
            try:
                return await self.search_code(query, owner=owner, repo=repo, **kwargs)
            except Exception:
                pass

        # 所有通路都失败
        raise RuntimeError("所有搜索通路都不可用")
