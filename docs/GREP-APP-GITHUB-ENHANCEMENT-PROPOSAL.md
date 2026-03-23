# grep-app MCP 增强方案 - GitHub 集成

**提案日期**: 2026-03-23  
**状态**: 📋 提案阶段  
**优先级**: ⭐⭐⭐⭐ 高

---

## 📋 提案概述

### 当前状态

**OML grep-app MCP** (本地实现):
- ✅ 本地代码搜索 (GNU grep)
- ✅ 自然语言搜索
- ✅ 正则表达式搜索
- ✅ 统计/列出文件
- ❌ **仅限本地代码库**

### 增强方案

**添加 GitHub 远程搜索能力**:

```
grep-app MCP (增强版)
├── 本地搜索 (GNU grep) ✅ 已有
└── GitHub 搜索 (新增) ⚪
    ├── git CLI (克隆/拉取)
    ├── gh CLI (GitHub API)
    └── Python (处理/缓存)
```

---

## 🎯 功能对比

### ai-tools-all/grep_app_mcp (参考)

| 功能 | 实现方式 |
|------|---------|
| **搜索 GitHub** | grep.app API |
| **获取文件** | grep.app API |
| **批量获取** | grep.app API |
| **缓存** | 本地 SQLite |

### OML grep-app (增强方案)

| 功能 | 实现方式 |
|------|---------|
| **搜索 GitHub** | `gh search code` + `git clone` |
| **获取文件** | `git show` + 本地读取 |
| **批量获取** | `git archive` + Python 处理 |
| **缓存** | 本地 Git 仓库 + SQLite |

**优势**:
- ✅ 无需外部 API (使用官方 GitHub API)
- ✅ 完整 Git 历史
- ✅ 离线访问已克隆仓库
- ✅ 隐私安全 (代码不发送到第三方)

---

## 🔧 技术实现

### 依赖工具

```bash
# 必需工具
git          # Git 版本控制
gh           # GitHub CLI
python3      # Python 运行时

# Python 依赖
mcp          # MCP SDK
pydantic     # 数据验证
sqlite3      # 缓存数据库
```

### 安装脚本

```bash
#!/usr/bin/env bash
# 安装依赖

# Termux
pkg install git python3

# GitHub CLI
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd /etc/apt/trusted.gpg.d/githubcli-archive-keyring.gpg
sudo apt update
sudo apt install gh

# Python 依赖
pip install mcp pydantic
```

---

## 📁 增强架构

### 目录结构

```
plugins/mcps/grep-app/
├── src/grep_app_mcp/
│   ├── __init__.py          # 主入口
│   ├── local_search.py      # 本地搜索 (已有)
│   ├── github_search.py     # GitHub 搜索 (新增) ⚪
│   ├── cache_manager.py     # 缓存管理 (新增) ⚪
│   └── github_client.py     # GitHub 客户端 (新增) ⚪
├── scripts/
│   ├── install.sh           # 安装脚本 (新增) ⚪
│   └── setup-gh.sh          # gh 配置脚本 (新增) ⚪
└── tests/
    ├── test_github_search.py  # GitHub 搜索测试 (新增) ⚪
    └── test_cache.py          # 缓存测试 (新增) ⚪
```

---

## 🔍 新增 MCP 工具

### 1. github_search_code

**功能**: 搜索 GitHub 代码

**输入**:
```json
{
  "query": "async await example",
  "language": "python",
  "max_results": 10
}
```

**实现**:
```python
async def github_search_code(query: str, language: str = None, max_results: int = 10):
    # 使用 gh CLI 搜索
    cmd = ["gh", "search", "code", query]
    if language:
        cmd.extend(["--language", language])
    cmd.extend(["--limit", str(max_results)])
    cmd.extend(["--json", "path,repository,url"])
    
    result = subprocess.run(cmd, capture_output=True, text=True)
    return json.loads(result.stdout)
```

---

### 2. github_clone_repo

**功能**: 克隆 GitHub 仓库到本地缓存

**输入**:
```json
{
  "repository": "owner/repo",
  "branch": "main",
  "depth": 1
}
```

**实现**:
```python
async def github_clone_repo(repository: str, branch: str = "main", depth: int = 1):
    cache_dir = get_cache_dir() / repository
    cmd = ["git", "clone", "--depth", str(depth), "--branch", branch,
           f"https://github.com/{repository}.git", str(cache_dir)]
    
    subprocess.run(cmd, check=True)
    return {"status": "success", "path": str(cache_dir)}
```

---

### 3. github_get_file

**功能**: 获取仓库中的文件内容

**输入**:
```json
{
  "repository": "owner/repo",
  "path": "src/main.py",
  "ref": "main"
}
```

**实现**:
```python
async def github_get_file(repository: str, path: str, ref: str = "main"):
    # 先从缓存读取
    cache_file = get_cache_dir() / repository / path
    if cache_file.exists():
        return cache_file.read_text()
    
    # 缓存未命中，使用 gh CLI 获取
    cmd = ["gh", "api", f"/repos/{repository}/contents/{path}",
           "--field", f"ref={ref}"]
    result = subprocess.run(cmd, capture_output=True, text=True)
    data = json.loads(result.stdout)
    
    # 解码 Base64 内容
    content = base64.b64decode(data["content"]).decode()
    
    # 写入缓存
    cache_file.parent.mkdir(parents=True, exist_ok=True)
    cache_file.write_text(content)
    
    return content
```

---

### 4. github_list_repo_files

**功能**: 列出仓库文件

**输入**:
```json
{
  "repository": "owner/repo",
  "path": "src/",
  "recursive": false
}
```

**实现**:
```python
async def github_list_repo_files(repository: str, path: str = "", recursive: bool = False):
    cache_dir = get_cache_dir() / repository
    
    # 如果未克隆，先克隆
    if not cache_dir.exists():
        await github_clone_repo(repository)
    
    # 列出文件
    target_path = cache_dir / path
    files = []
    
    if recursive:
        for f in target_path.rglob("*"):
            if f.is_file():
                files.append(str(f.relative_to(cache_dir)))
    else:
        for f in target_path.iterdir():
            files.append(str(f.relative_to(cache_dir)))
    
    return {"files": files, "repository": repository}
```

---

## 📊 缓存策略

### 缓存目录结构

```
~/.cache/grep-app/github/
├── owner1/
│   └── repo1/
│       ├── .git/
│       ├── src/
│       └── README.md
├── owner2/
│   └── repo2/
│       └── ...
└── cache.db  # SQLite 缓存数据库
```

### 缓存管理

```python
class GitHubCacheManager:
    def __init__(self):
        self.cache_dir = Path.home() / ".cache" / "grep-app" / "github"
        self.db_path = self.cache_dir / "cache.db"
        self._init_db()
    
    def _init_db(self):
        """初始化 SQLite 数据库"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS repos (
                id INTEGER PRIMARY KEY,
                repository TEXT UNIQUE,
                last_updated TIMESTAMP,
                commit_hash TEXT
            )
        """)
        conn.commit()
        conn.close()
    
    def is_cache_valid(self, repository: str, max_age_hours: int = 24) -> bool:
        """检查缓存是否有效"""
        # 检查最后更新时间
        pass
    
    def update_cache(self, repository: str, commit_hash: str):
        """更新缓存元数据"""
        pass
    
    def cleanup(self, max_age_days: int = 7):
        """清理过期缓存"""
        pass
```

---

## 🔐 认证配置

### gh CLI 认证

```bash
# GitHub 认证
gh auth login

# 选择 GitHub.com
# 选择 HTTPS
# 复制 One-Time Code
# 浏览器授权
```

### 权限说明

**必需权限**:
- `repo` - 访问私有仓库 (可选)
- `read:org` - 读取组织信息 (可选)

**最小权限** (仅公开仓库):
- 无需额外权限

---

## 📋 实施计划

### Phase 1: 基础实现 (3 天)

- [ ] 创建 `github_client.py`
- [ ] 实现 `github_search_code`
- [ ] 实现 `github_clone_repo`
- [ ] 实现 `github_get_file`
- [ ] 添加基础测试

### Phase 2: 缓存系统 (2 天)

- [ ] 创建 `cache_manager.py`
- [ ] 实现 SQLite 缓存
- [ ] 实现 Git 仓库缓存
- [ ] 添加缓存清理
- [ ] 添加缓存测试

### Phase 3: 优化和文档 (2 天)

- [ ] 性能优化
- [ ] 错误处理
- [ ] 用户文档
- [ ] 安装脚本
- [ ] 完整测试

---

## 📊 依赖对比

| 依赖 | ai-tools-all | OML (增强后) | 说明 |
|------|-------------|-------------|------|
| **外部 API** | ✅ grep.app | ❌ 无 | 使用官方 GitHub API |
| **git** | ❌ | ✅ | 本地 Git |
| **gh CLI** | ❌ | ✅ | GitHub 官方 CLI |
| **Python** | ✅ | ✅ | 运行时 |
| **SQLite** | ✅ | ✅ | 缓存数据库 |

---

## ✅ 优势分析

### 相比 ai-tools-all/grep_app_mcp

| 方面 | ai-tools-all | OML (增强后) | 优势 |
|------|-------------|-------------|------|
| **API 依赖** | ✅ 第三方 API | ❌ 官方 API | ✅ 更稳定 |
| **隐私** | ⚠️ 发送到第三方 | ✅ 本地缓存 | ✅ 更安全 |
| **离线访问** | ❌ | ✅ 已克隆仓库 | ✅ 更灵活 |
| **Git 历史** | ❌ | ✅ 完整历史 | ✅ 更强大 |
| **速率限制** | ⚠️ API 限制 | ✅ GitHub API 限制 | ✅ 更宽松 |
| **成本** | ⚠️ 可能收费 | ✅ 免费 | ✅ 更经济 |

---

## 🔗 相关资源

- [GitHub CLI 文档](https://cli.github.com/)
- [GitHub Search API](https://docs.github.com/en/rest/search)
- [MCP SDK 文档](https://modelcontextprotocol.io/)
- [ai-tools-all/grep_app_mcp](https://github.com/ai-tools-all/grep_app_mcp)

---

**提案者**: OML Team  
**提案日期**: 2026-03-23  
**状态**: 📋 待审批
