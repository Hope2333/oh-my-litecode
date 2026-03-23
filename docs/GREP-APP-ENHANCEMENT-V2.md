# grep-app MCP 增强方案 v2 - 本地优先 + 双通路联网

**提案日期**: 2026-03-23  
**版本**: 2.0  
**状态**: 📋 提案阶段  
**优先级**: ⭐⭐⭐⭐⭐ 最高

---

## 📋 设计原则

### 1. 本地优先 (Local-First)

```
搜索请求
    │
    ▼
┌─────────────────┐
│  本地缓存搜索   │ ← 第一优先级
│  (Git 仓库)     │
└────────┬────────┘
         │ 未命中
         ▼
┌─────────────────┐
│  远程搜索       │ ← 备用
└─────────────────┘
```

**优势**:
- ✅ 离线可用
- ✅ 隐私安全
- ✅ 低延迟
- ✅ 无 API 限制

---

### 2. 双通路联网

```
远程搜索
    │
    ├──────────────┬──────────────┐
    ▼              ▼              ▼
┌─────────┐  ┌─────────┐  ┌─────────┐
│ gh CLI  │  │ 爬虫    │  │ 第三方  │
│ (优先)  │  │ (备用)  │  │ API     │
└─────────┘  └─────────┘  └─────────┘
```

**通路说明**:

| 通路 | 优先级 | 用途 | 状态 |
|------|--------|------|------|
| **gh CLI** | ⭐⭐⭐⭐⭐ | GitHub 官方 CLI | 首选 |
| **爬虫** | ⭐⭐⭐ | GitHub/GitLab 网页抓取 | 备用 |
| **第三方 API** | ⭐⭐ | Sourcegraph 等 | 可选 |

---

## 🎯 功能架构

### 完整架构图

```
┌─────────────────────────────────────────────────────────┐
│                    grep-app MCP                          │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌──────────────────────────────────────────────────┐  │
│  │              本地搜索层 (Local-First)             │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌───────────┐ │  │
│  │  │ GNU grep    │  │ AST 搜索    │  │ 缓存管理  │ │  │
│  │  │ (代码搜索)  │  │ (语义搜索)  │  │ (SQLite)  │ │  │
│  │  └─────────────┘  └─────────────┘  └───────────┘ │  │
│  └──────────────────────────────────────────────────┘  │
│                         │ 未命中                        │
│                         ▼                               │
│  ┌──────────────────────────────────────────────────┐  │
│  │                远程搜索层 (联网)                  │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌───────────┐ │  │
│  │  │ gh CLI      │  │ 爬虫        │  │ 第三方    │ │  │
│  │  │ (GitHub)    │  │ (通用)      │  │ API       │ │  │
│  │  │ ⭐⭐⭐⭐⭐     │  │ ⭐⭐⭐        │  │ ⭐⭐       │ │  │
│  │  └─────────────┘  └─────────────┘  └───────────┘ │  │
│  └──────────────────────────────────────────────────┘  │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

---

## 🔧 通路 1: gh CLI (首选)

### 安装和配置

```bash
# 安装 gh CLI
# Termux
pkg install gh

# Arch Linux
sudo pacman -S gh

# Debian/Ubuntu
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd /etc/apt/trusted.gpg.d/githubcli-archive-keyring.gpg
sudo apt update
sudo apt install gh

# 认证
gh auth login
```

### 功能实现

#### github_search_code

```python
async def github_search_code(
    query: str,
    language: str = None,
    repo: str = None,
    max_results: int = 10
) -> list:
    """
    使用 gh CLI 搜索 GitHub 代码
    
    Args:
        query: 搜索查询
        language: 编程语言过滤
        repo: 仓库过滤 (owner/repo)
        max_results: 最大结果数
    
    Returns:
        搜索结果列表
    """
    import subprocess
    import json
    
    # 构建 gh 命令
    cmd = ["gh", "search", "code", query]
    
    if language:
        cmd.extend(["--language", language])
    
    if repo:
        cmd.extend(["--repo", repo])
    
    cmd.extend(["--limit", str(max_results)])
    cmd.extend(["--json", "path,repository,url,name"])
    
    # 执行命令
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30
        )
        
        if result.returncode != 0:
            return {"error": result.stderr}
        
        return json.loads(result.stdout)
    
    except subprocess.TimeoutExpired:
        return {"error": "Search timeout"}
    except FileNotFoundError:
        return {"error": "gh CLI not found, please install it"}
```

#### github_get_file

```python
async def github_get_file(
    repository: str,
    path: str,
    ref: str = "main"
) -> str:
    """
    使用 gh API 获取文件内容
    
    Args:
        repository: 仓库名 (owner/repo)
        path: 文件路径
        ref: 分支/标签
    
    Returns:
        文件内容
    """
    import subprocess
    import base64
    import json
    
    # 使用 gh API 获取
    cmd = [
        "gh", "api",
        f"/repos/{repository}/contents/{path}",
        "--field", f"ref={ref}"
    ]
    
    result = subprocess.run(cmd, capture_output=True, text=True)
    
    if result.returncode != 0:
        return f"Error: {result.stderr}"
    
    data = json.loads(result.stdout)
    
    # 解码 Base64 内容
    content = base64.b64decode(data["content"]).decode("utf-8")
    
    return content
```

---

## 🕷️ 通路 2: 爬虫 (备用)

### 设计思路

当 gh CLI 不可用时，使用爬虫作为备用方案：
- 无需认证
- 支持 GitHub/GitLab 等
- 遵守 robots.txt
- 速率限制

### 实现方案

#### 方案 A: 使用现有库

**推荐库**: `github-search` (Python)

```python
# 安装
pip install github-search

# 使用
from github_search import search_code

results = search_code(
    query="async await",
    language="python",
    per_page=10
)
```

#### 方案 B: 自主实现爬虫

```python
async def web_search_github(
    query: str,
    language: str = None,
    max_results: int = 10
) -> list:
    """
    通过网页抓取搜索 GitHub (备用方案)
    
    注意：此方案仅作为 gh CLI 不可用时的备用
    """
    import httpx
    from bs4 import BeautifulSoup
    
    # 构建搜索 URL
    url = "https://github.com/search"
    params = {"q": query, "type": "code"}
    
    if language:
        params["l"] = language
    
    async with httpx.AsyncClient() as client:
        response = await client.get(url, params=params)
        response.raise_for_status()
        
        # 解析 HTML
        soup = BeautifulSoup(response.text, 'html.parser')
        results = []
        
        # 提取搜索结果
        for item in soup.select(".code-list-item"):
            repo_elem = item.select_one(".code-list-item-owner a")
            path_elem = item.select_one(".code-list-item-content")
            
            if repo_elem and path_elem:
                results.append({
                    "repository": repo_elem.text.strip(),
                    "path": path_elem.get("title", ""),
                    "url": f"https://github.com{repo_elem.get('href')}"
                })
                
                if len(results) >= max_results:
                    break
        
        return results
```

---

## 🌐 通路 3: 第三方 API (可选)

### Sourcegraph API

```python
async def sourcegraph_search(
    query: str,
    max_results: int = 10
) -> list:
    """
    使用 Sourcegraph API 搜索代码
    
    支持：GitHub, GitLab, Bitbucket 等
    """
    import httpx
    
    url = "https://sourcegraph.com/.api/search"
    
    payload = {
        "query": query,
        "version": "V3",
        "patternType": "literal"
    }
    
    async with httpx.AsyncClient() as client:
        response = await client.post(url, json=payload)
        response.raise_for_status()
        data = response.json()
        
        results = []
        for result in data.get("results", {}).get("results", []):
            results.append({
                "repository": result.get("repository", {}).get("name"),
                "path": result.get("file", {}).get("path"),
                "url": result.get("url")
            })
            
            if len(results) >= max_results:
                break
        
        return results
```

---

## 📁 完整目录结构

```
plugins/mcps/grep-app/
├── src/grep_app_mcp/
│   ├── __init__.py              # 主入口
│   ├── local_search.py          # 本地搜索 (已有)
│   ├── remote_search.py         # 远程搜索 (新增) ⚪
│   │   ├── github_gh_cli.py     # gh CLI 通路
│   │   ├── github_web_scraper.py# 爬虫通路
│   │   └── third_party_api.py   # 第三方 API
│   ├── cache_manager.py         # 缓存管理 (新增) ⚪
│   │   ├── git_cache.py         # Git 仓库缓存
│   │   └── sqlite_cache.py      # SQLite 元数据
│   └── fallback_strategy.py     # 降级策略 (新增) ⚪
├── scripts/
│   ├── install.sh               # 安装脚本
│   └── setup-gh.sh              # gh 配置脚本
└── tests/
    ├── test_remote_search.py    # 远程搜索测试
    ├── test_cache.py            # 缓存测试
    └── test_fallback.py         # 降级测试
```

---

## 🔄 降级策略

### 智能降级流程

```python
async def search_code_with_fallback(query: str, **kwargs):
    """
    智能降级搜索策略
    
    优先级:
    1. 本地缓存 (最快，离线可用)
    2. gh CLI (官方 API，稳定)
    3. 爬虫 (备用，无需认证)
    4. 第三方 API (最后手段)
    """
    
    # 1. 本地缓存搜索
    local_results = await local_search(query, **kwargs)
    if local_results:
        log_info("Found results in local cache")
        return local_results
    
    # 2. gh CLI 搜索
    try:
        gh_results = await github_gh_cli_search(query, **kwargs)
        if gh_results:
            log_info("Found results via gh CLI")
            # 缓存结果
            await cache_results(query, gh_results)
            return gh_results
    except Exception as e:
        log_warning(f"gh CLI failed: {e}")
    
    # 3. 爬虫搜索
    try:
        scraper_results = await github_web_scraper_search(query, **kwargs)
        if scraper_results:
            log_info("Found results via web scraper")
            await cache_results(query, scraper_results)
            return scraper_results
    except Exception as e:
        log_warning(f"Web scraper failed: {e}")
    
    # 4. 第三方 API
    try:
        api_results = await sourcegraph_search(query, **kwargs)
        if api_results:
            log_info("Found results via third-party API")
            await cache_results(query, api_results)
            return api_results
    except Exception as e:
        log_error(f"All search methods failed: {e}")
    
    return {"error": "No results found from any source"}
```

---

## 📊 通路对比

| 通路 | 速度 | 稳定性 | 隐私 | 离线 | 推荐度 |
|------|------|--------|------|------|--------|
| **本地缓存** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ✅ | ⭐⭐⭐⭐⭐ |
| **gh CLI** | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ❌ | ⭐⭐⭐⭐⭐ |
| **爬虫** | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ | ❌ | ⭐⭐⭐ |
| **第三方 API** | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐ | ❌ | ⭐⭐ |

---

## 🎯 实施计划

### Phase 1: gh CLI 集成 (2 天)

- [ ] 创建 `github_gh_cli.py`
- [ ] 实现 `github_search_code`
- [ ] 实现 `github_get_file`
- [ ] 添加 gh 安装检测
- [ ] 添加认证检查

### Phase 2: 爬虫备用 (3 天)

- [ ] 创建 `github_web_scraper.py`
- [ ] 实现 HTML 解析
- [ ] 添加速率限制
- [ ] 遵守 robots.txt
- [ ] 添加错误处理

### Phase 3: 缓存系统 (2 天)

- [ ] 创建 Git 仓库缓存
- [ ] 实现 SQLite 元数据
- [ ] 添加缓存清理
- [ ] 实现缓存预热

### Phase 4: 降级策略 (2 天)

- [ ] 创建 `fallback_strategy.py`
- [ ] 实现智能降级
- [ ] 添加日志记录
- [ ] 完整测试

---

## ✅ 优势总结

### 相比单一 gh CLI 方案

| 方面 | 单一 gh | 双通路 + 降级 | 提升 |
|------|--------|-------------|------|
| **可用性** | ⚠️ gh 故障时不可用 | ✅ 自动降级 | +99% |
| **离线支持** | ❌ | ✅ 本地缓存 | ✅ |
| **多平台** | ⚠️ GitHub only | ✅ GitHub+GitLab | +50% |
| **隐私** | ⚠️ 发送到 GitHub | ✅ 本地优先 | ✅ |
| **速度** | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ (缓存) | +25% |

---

## 🔗 相关资源

- [GitHub CLI 文档](https://cli.github.com/)
- [Sourcegraph API](https://docs.sourcegraph.com/api)
- [robots.txt 规范](https://www.robotstxt.org/)
- [Git 本地缓存最佳实践](https://git-scm.com/book/en/v2/Git-Tools-Caching)

---

**提案者**: OML Team  
**版本**: 2.0  
**提案日期**: 2026-03-23  
**状态**: 📋 待审批
