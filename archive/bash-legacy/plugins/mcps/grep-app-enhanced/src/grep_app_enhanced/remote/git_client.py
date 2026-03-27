"""
Git Client - Git 命令通路封装.

本模块提供对 Git 命令行的封装，支持：
- 仓库克隆（支持浅克隆）
- 分支操作
- 文件历史
- 差异比较
- 提交搜索
- 远程通路集成（GitHub/GitLab/Gitee）

Example:
    ```python
    from grep_app_enhanced.remote import GitClient

    git = GitClient()
    await git.clone_repository("https://github.com/owner/repo", "/tmp/repo", depth=1)

    content = await git.get_file_content("/tmp/repo", "HEAD:src/main.py")
    results = await git.search_in_repo("/tmp/repo", "def main")
    await git.pull_latest("/tmp/repo")
    ```

Supported Commands:
    - clone_repository: 克隆仓库（支持浅克隆）
    - pull_latest: 拉取更新
    - get_file_content: 获取文件内容 (git show)
    - search_in_repo: 本地 grep 搜索
    - log: 查看提交历史
    - diff: 比较差异
    - ls-files: 列出文件
    - blame: 追溯变更

Supported Platforms:
    - GitHub: https://github.com/owner/repo
    - GitLab: https://gitlab.com/owner/repo
    - Gitee: https://gitee.com/owner/repo
    - 其他标准 Git 仓库

Author:
    Oh My LiteCode Team
"""

from __future__ import annotations

import asyncio
import json
import shutil
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, AsyncIterator


@dataclass
class GitCommit:
    """Git 提交数据类.

    Attributes:
        sha: 提交哈希
        short_sha: 短哈希
        author: 作者名
        author_email: 作者邮箱
        date: 提交日期
        message: 提交消息
        parents: 父提交列表

    Example:
        ```python
        commit = GitCommit(
            sha="abc123...",
            author="John Doe",
            message="Fix bug"
        )
        ```
    """

    sha: str
    short_sha: str = ""
    author: str = ""
    author_email: str = ""
    date: str = ""
    message: str = ""
    parents: list[str] = field(default_factory=list)

    @property
    def subject(self) -> str:
        """获取提交标题（第一行）."""
        return self.message.split("\n")[0] if self.message else ""

    @classmethod
    def from_log_line(cls, line: str) -> GitCommit:
        """从 git log 输出行解析.

        Args:
            line: 格式化的 log 行

        Returns:
            GitCommit 实例
        """
        parts = line.split("\x00")
        if len(parts) >= 6:
            return cls(
                sha=parts[0],
                short_sha=parts[1],
                author=parts[2],
                author_email=parts[3],
                date=parts[4],
                message=parts[5],
                parents=parts[6].split() if len(parts) > 6 and parts[6] else [],
            )
        return cls(sha=line)


@dataclass
class GitFile:
    """Git 文件数据类.

    Attributes:
        path: 文件路径
        status: 文件状态 (added, modified, deleted, etc.)
        mode: 文件模式

    Example:
        ```python
        file = GitFile(
            path="src/main.py",
            status="modified"
        )
        ```
    """

    path: str
    status: str = ""
    mode: str = ""


@dataclass
class GitBlame:
    """Git blame 数据类.

    Attributes:
        line_number: 行号
        content: 行内容
        commit_sha: 提交哈希
        author: 作者
        date: 日期

    Example:
        ```python
        blame = GitBlame(
            line_number=42,
            content="def main():",
            author="John Doe"
        )
        ```
    """

    line_number: int
    content: str
    commit_sha: str = ""
    author: str = ""
    date: str = ""


class GitClient:
    """Git 命令行封装类.

    提供对 Git 命令的封装，支持各种 Git 操作.

    Attributes:
        git_path: git 可执行文件路径
        timeout: 命令超时时间（秒）

    Example:
        ```python
        git = GitClient(timeout=60)
        await git.clone("https://github.com/...", "/tmp/repo")

        commits = await git.log("/tmp/repo", max_count=10)
        for commit in commits:
            print(f"{commit.short_sha}: {commit.subject}")
        ```

    Note:
        - 所有操作都是异步的
        - 支持大仓库操作
        - 自动处理命令错误
    """

    DEFAULT_TIMEOUT = 60

    def __init__(
        self,
        git_path: str | None = None,
        timeout: int = DEFAULT_TIMEOUT,
    ) -> None:
        """初始化 Git 客户端.

        Args:
            git_path: git 可执行文件路径（自动检测如果为 None）
            timeout: 命令超时时间（秒）

        Raises:
            FileNotFoundError: git 未安装
        """
        self.git_path = git_path or shutil.which("git")
        self.timeout = timeout

        if not self.git_path:
            raise FileNotFoundError("git 未安装或不在 PATH 中")

    async def _run_command(
        self,
        args: list[str],
        cwd: str | Path | None = None,
        capture_output: bool = True,
    ) -> tuple[int, str, str]:
        """运行 Git 命令.

        Args:
            args: 命令参数（不包含 'git'）
            cwd: 工作目录
            capture_output: 是否捕获输出

        Returns:
            (返回码，stdout, stderr)

        Raises:
            asyncio.TimeoutError: 命令超时
        """
        cmd = [self.git_path] + args

        try:
            process = await asyncio.create_subprocess_exec(
                *cmd,
                cwd=str(cwd) if cwd else None,
                stdout=asyncio.subprocess.PIPE if capture_output else None,
                stderr=asyncio.subprocess.PIPE if capture_output else None,
            )

            if capture_output:
                stdout, stderr = await asyncio.wait_for(
                    process.communicate(),
                    timeout=self.timeout,
                )
                return (
                    process.returncode or 0,
                    stdout.decode("utf-8", errors="replace"),
                    stderr.decode("utf-8", errors="replace"),
                )
            else:
                await asyncio.wait_for(process.wait(), timeout=self.timeout)
                return (process.returncode or 0, "", "")

        except asyncio.TimeoutError:
            process.kill()
            await process.wait()
            raise

    async def clone(
        self,
        url: str,
        dest: str | Path,
        branch: str | None = None,
        depth: int | None = None,
        bare: bool = False,
    ) -> None:
        """克隆仓库.

        Args:
            url: 仓库 URL
            dest: 目标路径
            branch: 分支名
            depth: 浅克隆深度
            bare: 是否创建裸仓库

        Raises:
            RuntimeError: 克隆失败
        """
        args = ["clone"]

        if branch:
            args.extend(["-b", branch])
        if depth:
            args.extend(["--depth", str(depth)])
        if bare:
            args.append("--bare")

        args.extend([url, str(dest)])

        returncode, stdout, stderr = await self._run_command(args)

        if returncode != 0:
            raise RuntimeError(f"git clone 失败：{stderr}")

    async def pull(
        self,
        repo_path: str | Path,
        remote: str = "origin",
        branch: str | None = None,
    ) -> None:
        """拉取更新.

        Args:
            repo_path: 仓库路径
            remote: 远程名
            branch: 分支名

        Raises:
            RuntimeError: 拉取失败
        """
        args = ["pull"]

        if remote:
            args.append(remote)
        if branch:
            args.append(branch)

        returncode, stdout, stderr = await self._run_command(args, cwd=repo_path)

        if returncode != 0:
            raise RuntimeError(f"git pull 失败：{stderr}")

    async def log(
        self,
        repo_path: str | Path,
        max_count: int = 100,
        since: str | None = None,
        until: str | None = None,
        path: str | None = None,
        format_str: str = "%H\x00%h\x00%an\x00%ae\x00%ai\x00%s\x00%P",
    ) -> list[GitCommit]:
        """查看提交历史.

        Args:
            repo_path: 仓库路径
            max_count: 最大提交数
            since: 起始时间
            until: 结束时间
            path: 文件路径过滤
            format_str: 输出格式

        Returns:
            提交列表
        """
        args = [
            "log",
            f"-n{max_count}",
            f"--format={format_str}",
            "--null",
        ]

        if since:
            args.extend(["--since", since])
        if until:
            args.extend(["--until", until])
        if path:
            args.extend(["--", str(path)])

        returncode, stdout, stderr = await self._run_command(args, cwd=repo_path)

        if returncode != 0:
            return []

        commits = []
        for line in stdout.strip().split("\n"):
            if line:
                commits.append(GitCommit.from_log_line(line))

        return commits

    async def diff(
        self,
        repo_path: str | Path,
        ref1: str = "HEAD",
        ref2: str | None = None,
        path: str | None = None,
        cached: bool = False,
    ) -> str:
        """比较差异.

        Args:
            repo_path: 仓库路径
            ref1: 第一个引用
            ref2: 第二个引用
            path: 文件路径过滤
            cached: 是否比较暂存区

        Returns:
            差异内容
        """
        args = ["diff"]

        if cached:
            args.append("--cached")

        if ref2:
            args.extend([ref1, ref2])
        elif ref1 != "HEAD":
            args.append(ref1)

        if path:
            args.extend(["--", str(path)])

        returncode, stdout, stderr = await self._run_command(args, cwd=repo_path)

        if returncode != 0 and not stderr.startswith("fatal: ambiguous"):
            raise RuntimeError(f"git diff 失败：{stderr}")

        return stdout

    async def show(
        self,
        repo_path: str | Path,
        ref: str,
        path: str | None = None,
    ) -> str:
        """显示内容.

        Args:
            repo_path: 仓库路径
            ref: 引用（可以是 commit:path 格式）
            path: 文件路径

        Returns:
            文件内容
        """
        args = ["show", ref]

        returncode, stdout, stderr = await self._run_command(args, cwd=repo_path)

        if returncode != 0:
            raise RuntimeError(f"git show 失败：{stderr}")

        return stdout

    async def grep(
        self,
        repo_path: str | Path,
        pattern: str,
        ref: str | None = None,
        path: str | None = None,
        ignore_case: bool = True,
        line_number: bool = True,
    ) -> list[dict[str, Any]]:
        """在仓库中搜索.

        Args:
            repo_path: 仓库路径
            pattern: 搜索模式
            ref: 引用（搜索特定版本）
            path: 文件路径过滤
            ignore_case: 是否忽略大小写
            line_number: 是否显示行号

        Returns:
            匹配结果列表
        """
        args = ["grep"]

        if ref:
            args.insert(1, ref)

        if ignore_case:
            args.append("-i")
        if line_number:
            args.append("-n")

        args.extend(["-e", pattern])

        if path:
            args.extend(["--", str(path)])

        returncode, stdout, stderr = await self._run_command(args, cwd=repo_path)

        if returncode == 1:  # 无匹配
            return []
        if returncode != 0:
            raise RuntimeError(f"git grep 失败：{stderr}")

        results = []
        for line in stdout.strip().split("\n"):
            if line:
                parts = line.split(":", 2)
                if len(parts) >= 3:
                    results.append(
                        {
                            "file": parts[0],
                            "line": int(parts[1]),
                            "content": parts[2],
                        }
                    )
                elif len(parts) == 2:
                    results.append(
                        {
                            "file": parts[0],
                            "line": 0,
                            "content": parts[1],
                        }
                    )

        return results

    async def ls_files(
        self,
        repo_path: str | Path,
        cached: bool = True,
        others: bool = False,
        excluded: bool = False,
    ) -> list[GitFile]:
        """列出文件.

        Args:
            repo_path: 仓库路径
            cached: 是否列出暂存区文件
            others: 是否列出未跟踪文件
            excluded: 是否包含被排除的文件

        Returns:
            文件列表
        """
        args = ["ls-files"]

        if cached:
            args.append("--cached")
        if others:
            args.append("--others")
        if excluded:
            args.append("--exclude-standard")

        returncode, stdout, stderr = await self._run_command(args, cwd=repo_path)

        if returncode != 0:
            return []

        files = []
        for line in stdout.strip().split("\n"):
            if line:
                files.append(GitFile(path=line))

        return files

    async def blame(
        self,
        repo_path: str | Path,
        path: str,
        ref: str | None = None,
        lines: tuple[int, int] | None = None,
    ) -> list[GitBlame]:
        """追溯变更.

        Args:
            repo_path: 仓库路径
            path: 文件路径
            ref: 引用
            lines: 行范围 (start, end)

        Returns:
            blame 结果列表
        """
        args = ["blame", "--porcelain"]

        if ref:
            args.insert(1, ref)
        if lines:
            args.extend(["-L", f"{lines[0]},{lines[1]}"])

        args.extend(["--", str(path)])

        returncode, stdout, stderr = await self._run_command(args, cwd=repo_path)

        if returncode != 0:
            raise RuntimeError(f"git blame 失败：{stderr}")

        return self._parse_blame(stdout, path)

    def _parse_blame(self, output: str, path: str) -> list[GitBlame]:
        """解析 blame 输出.

        Args:
            output: blame 输出
            path: 文件路径

        Returns:
            blame 结果列表
        """
        results = []
        lines = output.split("\n")
        i = 0

        while i < len(lines):
            line = lines[i]
            if not line:
                i += 1
                continue

            # 解析提交信息行
            parts = line.split()
            if len(parts) >= 2:
                sha = parts[0]
                line_num = int(parts[2]) if len(parts) > 2 else 0

                # 读取后续行获取详细信息
                author = ""
                date = ""
                content = ""

                i += 1
                while i < len(lines) and lines[i].startswith("\t"):
                    content = lines[i][1:]  # 移除制表符
                    i += 1
                    break

                while i < len(lines) and not lines[i].startswith(sha[:40].split()[0] if sha else ""):
                    if lines[i].startswith("author "):
                        author = lines[i][7:]
                    elif lines[i].startswith("author-time "):
                        import time

                        timestamp = int(lines[i][12:])
                        date = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(timestamp))
                    elif lines[i] and not lines[i].startswith("\t"):
                        # 新的提交开始
                        break
                    i += 1

                results.append(
                    GitBlame(
                        line_number=line_num,
                        content=content,
                        commit_sha=sha,
                        author=author,
                        date=date,
                    )
                )
            else:
                i += 1

        return results

    async def get_current_branch(self, repo_path: str | Path) -> str | None:
        """获取当前分支.

        Args:
            repo_path: 仓库路径

        Returns:
            分支名，如果不在仓库中返回 None
        """
        args = ["branch", "--show-current"]
        returncode, stdout, stderr = await self._run_command(args, cwd=repo_path)

        if returncode != 0:
            return None

        return stdout.strip()

    async def get_remote_url(
        self,
        repo_path: str | Path,
        remote: str = "origin",
    ) -> str | None:
        """获取远程 URL.

        Args:
            repo_path: 仓库路径
            remote: 远程名

        Returns:
            远程 URL，如果不存在返回 None
        """
        args = ["remote", "get-url", remote]
        returncode, stdout, stderr = await self._run_command(args, cwd=repo_path)

        if returncode != 0:
            return None

        return stdout.strip()

    async def is_git_repo(self, repo_path: str | Path) -> bool:
        """检查是否为 Git 仓库.

        Args:
            repo_path: 仓库路径

        Returns:
            如果是 Git 仓库返回 True
        """
        args = ["rev-parse", "--is-inside-work-tree"]
        returncode, _, _ = await self._run_command(args, cwd=repo_path)
        return returncode == 0

    # =========================================================================
    # 远程通路增强方法
    # =========================================================================

    async def clone_repository(
        self,
        url: str,
        dest: str | Path,
        branch: str | None = None,
        depth: int | None = 1,
        bare: bool = False,
        single_branch: bool = True,
        timeout: int | None = None,
    ) -> dict[str, Any]:
        """克隆仓库（增强版，支持浅克隆和多平台）.

        Args:
            url: 仓库 URL (支持 GitHub/GitLab/Gitee)
            dest: 目标路径
            branch: 分支名（默认自动检测）
            depth: 浅克隆深度（None 表示完整克隆）
            bare: 是否创建裸仓库
            single_branch: 是否只克隆单个分支
            timeout: 命令超时时间（秒），None 使用默认值

        Returns:
            克隆结果字典，包含：
            - success: 是否成功
            - path: 克隆路径
            - branch: 分支名
            - commit: 最新提交哈希
            - platform: 检测到的平台

        Raises:
            RuntimeError: 克隆失败

        Example:
            ```python
            git = GitClient()
            result = await git.clone_repository(
                "https://github.com/owner/repo",
                "/tmp/repo",
                depth=1
            )
            print(f"克隆成功：{result['path']}")
            ```
        """
        import time

        start_time = time.perf_counter()
        dest_path = Path(dest)

        # 检测平台
        platform = self._detect_platform(url)

        args = ["clone", "--progress"]

        if branch:
            args.extend(["-b", branch])
        if depth:
            args.extend(["--depth", str(depth)])
        if bare:
            args.append("--bare")
        if single_branch and not bare:
            args.append("--single-branch")

        args.extend([url, str(dest_path)])

        # 使用自定义超时
        original_timeout = self.timeout
        if timeout:
            self.timeout = timeout

        try:
            returncode, stdout, stderr = await self._run_command(args)
            self.timeout = original_timeout

            if returncode != 0:
                raise RuntimeError(f"git clone 失败：{stderr}")

            # 获取克隆后的信息
            branch_name = await self.get_current_branch(dest_path)
            commit = await self._get_head_commit(dest_path)

            elapsed = time.perf_counter() - start_time

            return {
                "success": True,
                "path": str(dest_path),
                "branch": branch_name or "unknown",
                "commit": commit or "unknown",
                "platform": platform,
                "elapsed_seconds": round(elapsed, 2),
                "depth": depth,
            }

        except asyncio.TimeoutError:
            self.timeout = original_timeout
            raise RuntimeError(f"git clone 超时（{timeout}秒）")

    async def pull_latest(
        self,
        repo_path: str | Path,
        remote: str = "origin",
        branch: str | None = None,
        rebase: bool = False,
        timeout: int | None = None,
    ) -> dict[str, Any]:
        """拉取最新更改（支持断点续传）.

        Args:
            repo_path: 仓库路径
            remote: 远程名
            branch: 分支名（默认当前分支）
            rebase: 是否使用 rebase 模式
            timeout: 命令超时时间（秒）

        Returns:
            拉取结果字典，包含：
            - success: 是否成功
            - updated: 是否有更新
            - files_changed: 变更文件数
            - platform: 检测到的平台

        Raises:
            RuntimeError: 拉取失败
        """
        import time

        start_time = time.perf_counter()
        repo = Path(repo_path)

        if not await self.is_git_repo(repo):
            raise RuntimeError(f"不是 Git 仓库：{repo}")

        platform = self._detect_platform(await self.get_remote_url(repo) or "")

        args = ["pull"]

        if rebase:
            args.append("--rebase")
        else:
            args.append("--no-rebase")

        args.append(remote)
        if branch:
            args.append(branch)

        original_timeout = self.timeout
        if timeout:
            self.timeout = timeout

        try:
            returncode, stdout, stderr = await self._run_command(args, cwd=repo)
            self.timeout = original_timeout

            if returncode != 0:
                # 检查是否是"已经是最新"的情况
                if "Already up to date" in stderr or "Already up to date" in stdout:
                    return {
                        "success": True,
                        "updated": False,
                        "files_changed": 0,
                        "platform": platform,
                        "message": "已经是最新",
                    }
                raise RuntimeError(f"git pull 失败：{stderr}")

            # 解析变更统计
            files_changed = self._parse_pull_stats(stdout)
            elapsed = time.perf_counter() - start_time

            return {
                "success": True,
                "updated": files_changed > 0,
                "files_changed": files_changed,
                "platform": platform,
                "elapsed_seconds": round(elapsed, 2),
            }

        except asyncio.TimeoutError:
            self.timeout = original_timeout
            raise RuntimeError(f"git pull 超时（{timeout}秒）")

    async def get_file_content(
        self,
        repo_path: str | Path,
        ref: str,
        path: str | None = None,
        encoding: str = "utf-8",
    ) -> str:
        """获取文件内容（git show）.

        Args:
            repo_path: 仓库路径
            ref: 引用（可以是 commit:path 或 commit 格式）
            path: 文件路径（如果 ref 不包含路径）
            encoding: 文件编码

        Returns:
            文件内容

        Raises:
            RuntimeError: 获取失败
            FileNotFoundError: 文件不存在

        Example:
            ```python
            git = GitClient()
            # 使用 commit:path 格式
            content = await git.get_file_content("/tmp/repo", "HEAD:src/main.py")

            # 或分开指定
            content = await git.get_file_content("/tmp/repo", "HEAD", "src/main.py")
            ```
        """
        repo = Path(repo_path)

        if not await self.is_git_repo(repo):
            raise RuntimeError(f"不是 Git 仓库：{repo}")

        # 构建引用
        if ":" in ref and path is None:
            # ref 已经是 commit:path 格式
            full_ref = ref
        elif path:
            full_ref = f"{ref}:{path}"
        else:
            raise ValueError("必须提供 path 或 ref 包含 commit:path 格式")

        returncode, stdout, stderr = await self._run_command(
            ["show", full_ref], cwd=repo
        )

        if returncode != 0:
            if "does not exist" in stderr or "exists on disk, but not" in stderr:
                raise FileNotFoundError(f"文件不存在：{full_ref}")
            raise RuntimeError(f"git show 失败：{stderr}")

        return stdout

    async def search_in_repo(
        self,
        repo_path: str | Path,
        pattern: str,
        ref: str | None = None,
        path: str | None = None,
        extensions: list[str] | None = None,
        ignore_case: bool = True,
        line_number: bool = True,
        context_lines: int = 0,
        max_results: int | None = None,
    ) -> list[dict[str, Any]]:
        """在仓库中搜索内容（本地 grep）.

        Args:
            repo_path: 仓库路径
            pattern: 搜索模式（支持正则）
            ref: 引用（搜索特定版本，None 表示工作区）
            path: 路径过滤
            extensions: 文件扩展名过滤（如 [".py", ".js"]）
            ignore_case: 是否忽略大小写
            line_number: 是否显示行号
            context_lines: 上下文行数
            max_results: 最大结果数（None 表示不限制）

        Returns:
            搜索结果列表，每项包含：
            - file: 文件路径
            - line: 行号
            - content: 匹配内容
            - ref: 引用（如果指定）

        Raises:
            RuntimeError: 搜索失败

        Example:
            ```python
            git = GitClient()
            results = await git.search_in_repo(
                "/tmp/repo",
                "def main",
                extensions=[".py"],
                max_results=100
            )
            for r in results:
                print(f"{r['file']}:{r['line']}: {r['content']}")
            ```
        """
        repo = Path(repo_path)

        if not await self.is_git_repo(repo):
            raise RuntimeError(f"不是 Git 仓库：{repo}")

        args = ["grep"]

        if ref:
            args.insert(1, ref)

        if ignore_case:
            args.append("-i")
        if line_number:
            args.append("-n")
        if context_lines > 0:
            args.extend(["-C", str(context_lines)])

        # 扩展名过滤
        if extensions:
            for ext in extensions:
                args.extend(["--and", "-e", f"*{ext}"])
                # 实际上 git grep 不支持直接的扩展名过滤
                # 这里我们在后处理中过滤

        args.extend(["-e", pattern])

        if path:
            args.extend(["--", path])

        returncode, stdout, stderr = await self._run_command(args, cwd=repo)

        if returncode == 1:  # 无匹配
            return []
        if returncode != 0:
            raise RuntimeError(f"git grep 失败：{stderr}")

        results = []
        for line in stdout.strip().split("\n"):
            if not line:
                continue

            # 解析结果
            if context_lines > 0:
                # 带上下文的输出格式不同
                parts = line.split(":", 2)
            else:
                parts = line.split(":", 2)

            if len(parts) >= 3:
                file_path = parts[0]

                # 扩展名过滤
                if extensions:
                    file_ext = Path(file_path).suffix
                    if file_ext not in extensions:
                        continue

                try:
                    line_num = int(parts[1])
                except ValueError:
                    line_num = 0

                content = parts[2] if len(parts) > 2 else ""

                result = {
                    "file": file_path,
                    "line": line_num,
                    "content": content,
                }
                if ref:
                    result["ref"] = ref

                results.append(result)

                if max_results and len(results) >= max_results:
                    break

            elif len(parts) == 2:
                # 没有行号的情况
                file_path = parts[0]
                if extensions:
                    file_ext = Path(file_path).suffix
                    if file_ext not in extensions:
                        continue

                results.append({
                    "file": file_path,
                    "line": 0,
                    "content": parts[1],
                    "ref": ref if ref else None,
                })

        return results

    def _detect_platform(self, url: str) -> str:
        """检测 Git 平台类型.

        Args:
            url: 仓库 URL

        Returns:
            平台名称：github, gitlab, gitee, 或 generic
        """
        url_lower = url.lower()

        if "github.com" in url_lower:
            return "github"
        elif "gitlab.com" in url_lower:
            return "gitlab"
        elif "gitee.com" in url_lower:
            return "gitee"
        else:
            return "generic"

    async def _get_head_commit(self, repo_path: str | Path) -> str | None:
        """获取 HEAD 提交哈希.

        Args:
            repo_path: 仓库路径

        Returns:
            提交哈希，失败返回 None
        """
        returncode, stdout, stderr = await self._run_command(
            ["rev-parse", "HEAD"], cwd=repo_path
        )
        if returncode != 0:
            return None
        return stdout.strip()

    def _parse_pull_stats(self, output: str) -> int:
        """解析 git pull 输出的统计信息.

        Args:
            output: git pull 输出

        Returns:
            变更文件数
        """
        import re

        # 查找类似 "3 files changed" 的模式
        match = re.search(r"(\d+)\s+files?\s+changed", output)
        if match:
            return int(match.group(1))
        return 0

    async def fetch(
        self,
        repo_path: str | Path,
        remote: str = "origin",
        tags: bool = True,
        depth: int | None = None,
        unshallow: bool = False,
    ) -> dict[str, Any]:
        """获取远程更新（不合并）.

        Args:
            repo_path: 仓库路径
            remote: 远程名
            tags: 是否获取标签
            depth: 浅克隆深度
            unshallow: 是否转换为完整克隆

        Returns:
            获取结果
        """
        repo = Path(repo_path)

        args = ["fetch", remote]

        if tags:
            args.append("--tags")
        if depth:
            args.extend(["--depth", str(depth)])
        if unshallow:
            args.append("--unshallow")

        returncode, stdout, stderr = await self._run_command(args, cwd=repo)

        return {
            "success": returncode == 0,
            "stderr": stderr if returncode != 0 else "",
        }

    async def checkout(
        self,
        repo_path: str | Path,
        ref: str,
        create_branch: bool = False,
        force: bool = False,
    ) -> bool:
        """切换分支/标签.

        Args:
            repo_path: 仓库路径
            ref: 分支/标签名
            create_branch: 是否创建新分支
            force: 是否强制切换

        Returns:
            是否成功
        """
        repo = Path(repo_path)

        args = ["checkout"]

        if create_branch:
            args.append("-b")
        if force:
            args.append("-f")

        args.append(ref)

        returncode, _, _ = await self._run_command(args, cwd=repo)
        return returncode == 0
