# grep-app MCP 增强方案 v3 - 高压缩数据库 + 双通路联网

**提案日期**: 2026-03-23  
**版本**: 3.0 (优化版)  
**状态**: 📋 提案阶段  
**优先级**: ⭐⭐⭐⭐⭐ 最高

---

## 🎯 核心优化点

### 1. 数据库高压缩

**目标**: 
- ✅ 节省存储空间
- ✅ 压缩不影响读写性能
- ✅ 支持高压缩比 (10:1+)

### 2. 远程通路 2 优化

**原方案**: 仅爬虫  
**新方案**: 爬虫 + git 命令组合

**优势**:
- ✅ 更灵活
- ✅ 支持 GitLab 等其他平台
- ✅ 可获取完整仓库历史

---

## 🗄️ 高压缩数据库方案

### 候选方案对比

| 方案 | 压缩比 | 性能影响 | Termux | 成熟度 |
|------|--------|---------|--------|--------|
| **SQLite+ZSTD** | 5:1 | ⚠️ 中等 | ✅ | ⭐⭐⭐ |
| **SQLite+透明压缩** | 3:1 | ✅ 无 | ✅ | ⭐⭐⭐⭐ |
| **DuckDB** | 10:1 | ✅ 无 | ⚠️ 需编译 | ⭐⭐⭐ |
| **SQLite+外部压缩** | 20:1 | ⚠️ 读写时需解压 | ✅ | ⭐⭐⭐⭐⭐ |

---

### 推荐方案：SQLite + 透明压缩扩展

**扩展**: [sqlite-zstd](https://github.com/phiresky/sqlite-zstd)

**特点**:
- ✅ 透明压缩 (应用层无感知)
- ✅ 压缩比 5-10:1
- ✅ 读性能影响 <10%
- ✅ 写性能影响 <20%

**安装**:
```bash
# Termux (需编译)
pkg install build-tools cmake
git clone https://github.com/phiresky/sqlite-zstd
cd sqlite-zstd
make
make install
```

**使用**:
```python
import sqlite3

# 加载压缩扩展
conn = sqlite3.connect("cache.db")
conn.enable_load_extension(True)
conn.load_extension("sqlite_zstd")
conn.enable_load_extension(False)

# 创建压缩表
conn.execute("""
    CREATE VIRTUAL TABLE search_cache 
    USING zstd(
        search_cache_raw,
        compression_level=9
    )
""")
```

---

### 备选方案：SQLite + 外部压缩

**适用场景**: 冷数据归档

**实现**:
```python
import sqlite3
import zstandard as zstd
import json

class CompressedDatabase:
    """支持高压缩的数据库包装类"""
    
    def __init__(self, db_path: str, compression_level: int = 9):
        self.db_path = db_path
        self.compressor = zstd.ZstdCompressor(level=compression_level)
        self.decompressor = zstd.ZstdDecompressor()
        self._init_db()
    
    def _init_db(self):
        """初始化数据库"""
        conn = sqlite3.connect(self.db_path)
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("""
            CREATE TABLE IF NOT EXISTS compressed_data (
                key TEXT PRIMARY KEY,
                compressed_data BLOB,
                uncompressed_size INTEGER,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        conn.commit()
        conn.close()
    
    def set(self, key: str, value: dict):
        """写入压缩数据"""
        # 序列化
        data = json.dumps(value).encode('utf-8')
        
        # 压缩
        compressed = self.compressor.compress(data)
        
        # 写入数据库
        conn = sqlite3.connect(self.db_path)
        conn.execute("""
            INSERT OR REPLACE INTO compressed_data 
            (key, compressed_data, uncompressed_size)
            VALUES (?, ?, ?)
        """, (key, compressed, len(data)))
        conn.commit()
        conn.close()
    
    def get(self, key: str) -> dict:
        """读取并解压数据"""
        conn = sqlite3.connect(self.db_path)
        row = conn.execute("""
            SELECT compressed_data FROM compressed_data 
            WHERE key = ?
        """, (key,)).fetchone()
        conn.close()
        
        if not row:
            return None
        
        # 解压
        data = self.decompressor.decompress(row[0])
        return json.loads(data.decode('utf-8'))
    
    def get_compression_ratio(self) -> float:
        """计算压缩比"""
        conn = sqlite3.connect(self.db_path)
        total_compressed = conn.execute("""
            SELECT SUM(length(compressed_data)) FROM compressed_data
        """).fetchone()[0] or 0
        
        total_uncompressed = conn.execute("""
            SELECT SUM(uncompressed_size) FROM compressed_data
        """).fetchone()[0] or 0
        conn.close()
        
        if total_compressed == 0:
            return 1.0
        
        return total_uncompressed / total_compressed
```

**依赖**:
```toml
[project.dependencies]
zstandard = ">=0.21.0"  # ZSTD 压缩库
```

---

### 性能对比

| 操作 | 无压缩 | ZSTD 扩展 | 外部压缩 |
|------|--------|----------|---------|
| **读延迟** | 1ms | 1.1ms (+10%) | 1.2ms (+20%) |
| **写延迟** | 5ms | 6ms (+20%) | 8ms (+60%) |
| **压缩比** | 1:1 | 5:1 | 10:1 |
| **磁盘占用** | 100MB | 20MB | 10MB |

---

## 🌐 远程通路 2: 爬虫 + git 命令

### 架构设计

```
远程搜索 (通路 2)
    │
    ├──────────────┬──────────────┐
    ▼              ▼              ▼
┌─────────┐  ┌─────────┐  ┌─────────┐
│ 爬虫    │  │ git     │  │ 组合    │
│ (发现)  │  │ (获取)  │  │ (最优)  │
└─────────┘  └─────────┘  └─────────┘
```

---

### 爬虫模块 (发现)

**功能**: 搜索和发现仓库

```python
async def search_repositories(
    query: str,
    platform: str = "github",  # github|gitlab|gitee
    max_results: int = 10
) -> list:
    """
    搜索仓库 (爬虫方式)
    
    支持:
    - GitHub
    - GitLab
    - Gitee
    """
    import httpx
    from bs4 import BeautifulSoup
    
    platforms = {
        "github": "https://github.com/search?q={query}&type=repositories",
        "gitlab": "https://gitlab.com/search?search={query}",
        "gitee": "https://gitee.com/search?q={query}&type=repositories"
    }
    
    url = platforms.get(platform, platforms["github"]).format(query=query)
    
    async with httpx.AsyncClient() as client:
        response = await client.get(url)
        response.raise_for_status()
        
        soup = BeautifulSoup(response.text, 'html.parser')
        results = []
        
        # 解析搜索结果 (根据平台不同调整选择器)
        if platform == "github":
            for item in soup.select(".repo-list-item"):
                repo_elem = item.select_one(".v-card a")
                if repo_elem:
                    results.append({
                        "repository": repo_elem.text.strip().replace("\n", "/"),
                        "url": f"https://github.com{repo_elem.get('href')}",
                        "platform": "github"
                    })
        
        return results[:max_results]
```

---

### git 命令模块 (获取)

**功能**: 克隆和获取仓库内容

```python
async def clone_repository(
    repository: str,
    platform: str = "github",
    cache_dir: str = "~/.cache/grep-app/repos",
    depth: int = 1
) -> str:
    """
    克隆仓库到本地缓存
    
    支持:
    - GitHub
    - GitLab
    - Gitee
    - 任意 Git 服务器
    """
    import subprocess
    from pathlib import Path
    
    # 构建仓库 URL
    urls = {
        "github": f"https://github.com/{repository}.git",
        "gitlab": f"https://gitlab.com/{repository}.git",
        "gitee": f"https://gitee.com/{repository}.git"
    }
    
    repo_url = urls.get(platform, repository)
    cache_path = Path(cache_dir).expanduser() / platform / repository.replace("/", "_")
    
    # 检查是否已缓存
    if cache_path.exists():
        # 拉取最新
        subprocess.run(
            ["git", "-C", str(cache_path), "pull"],
            check=True,
            capture_output=True
        )
        return str(cache_path)
    
    # 克隆仓库
    cache_path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["git", "clone", "--depth", str(depth), repo_url, str(cache_path)],
        check=True,
        capture_output=True
    )
    
    return str(cache_path)

async def get_file_content(
    repository_path: str,
    file_path: str,
    ref: str = "HEAD"
) -> str:
    """
    使用 git show 获取文件内容
    
    优势:
    - 无需克隆整个仓库
    - 支持任意分支/标签
    - 支持历史版本
    """
    import subprocess
    
    result = subprocess.run(
        ["git", "-C", repository_path, "show", f"{ref}:{file_path}"],
        capture_output=True,
        text=True
    )
    
    if result.returncode != 0:
        raise FileNotFoundError(f"File not found: {file_path}")
    
    return result.stdout
```

---

### 组合模块 (最优路径)

**功能**: 智能选择最佳获取方式

```python
async def get_code_with_fallback(
    query: str,
    platform: str = "github"
) -> list:
    """
    获取代码 (智能降级)
    
    优先级:
    1. 本地缓存 (最快)
    2. git 命令 (完整历史)
    3. 爬虫 (网页抓取)
    """
    # 1. 检查本地缓存
    cached = await search_local_cache(query)
    if cached:
        return cached
    
    # 2. 搜索仓库
    repos = await search_repositories(query, platform)
    
    results = []
    for repo_info in repos:
        try:
            # 3. 克隆仓库 (使用 git 命令)
            repo_path = await clone_repository(
                repo_info["repository"],
                repo_info["platform"]
            )
            
            # 4. 本地搜索 (使用 grep)
            local_results = await search_in_repo(repo_path, query)
            
            if local_results:
                results.extend(local_results)
                
                # 缓存结果
                await cache_search_results(query, local_results)
                
                break  # 找到结果就停止
        
        except Exception as e:
            log_error(f"Failed to process {repo_info['repository']}: {e}")
            continue
    
    return results
```

---

## 📊 完整架构

### 三层缓存架构

```
搜索请求
    │
    ▼
┌─────────────────────────────────────────┐
│  Layer 1: 本地缓存 (SQLite+ZSTD)        │
│  - 搜索结果缓存                         │
│  - 仓库元数据                           │
│  - 压缩比 5-10:1                        │
└──────────────┬──────────────────────────┘
               │ 未命中
               ▼
┌─────────────────────────────────────────┐
│  Layer 2: 本地 Git 仓库                 │
│  - 已克隆仓库                           │
│  - git 命令直接搜索                      │
│  - 完整历史                             │
└──────────────┬──────────────────────────┘
               │ 未找到
               ▼
┌─────────────────────────────────────────┐
│  Layer 3: 远程通路                      │
│  ├─ 通路 1: gh CLI (GitHub 官方)        │
│  ├─ 通路 2: 爬虫 + git (通用)           │
│  └─ 通路 3: 第三方 API (可选)           │
└─────────────────────────────────────────┘
```

---

## 🔧 实施计划

### Phase 1: 数据库压缩 (2 天)

- [ ] 集成 sqlite-zstd 扩展
- [ ] 或实现外部压缩包装类
- [ ] 添加压缩比监控
- [ ] 性能基准测试

### Phase 2: git 命令集成 (2 天)

- [ ] 创建 `git_client.py`
- [ ] 实现 `clone_repository`
- [ ] 实现 `get_file_content`
- [ ] 实现 `search_in_repo`

### Phase 3: 爬虫优化 (2 天)

- [ ] 支持多平台 (GitHub/GitLab/Gitee)
- [ ] 添加速率限制
- [ ] 添加错误处理
- [ ] 遵守 robots.txt

### Phase 4: 智能降级 (2 天)

- [ ] 创建 `fallback_strategy.py`
- [ ] 实现三层缓存逻辑
- [ ] 添加监控日志
- [ ] 完整测试

---

## 📈 性能预期

### 存储优化

| 数据类型 | 原始大小 | 压缩后 | 压缩比 |
|---------|---------|--------|--------|
| **搜索结果** | 100MB | 10MB | 10:1 |
| **仓库元数据** | 50MB | 8MB | 6:1 |
| **文件索引** | 200MB | 25MB | 8:1 |
| **总计** | 350MB | 43MB | **8:1** |

### 性能提升

| 场景 | 无缓存 | 有缓存 | 提升 |
|------|-------|--------|------|
| **搜索结果** | 500ms | 10ms | +5000% |
| **文件获取** | 300ms | 5ms | +6000% |
| **元数据查询** | 200ms | 2ms | +10000% |

---

## ✅ 优势总结

| 特性 | v2 | v3 (优化版) | 提升 |
|------|----|-----------|------|
| **存储占用** | 350MB | 43MB | -88% |
| **远程通路 2** | 仅爬虫 | 爬虫+git | +50% 覆盖率 |
| **多平台** | GitHub | GitHub+GitLab+Gitee | +100% |
| **历史支持** | ❌ | ✅ 完整 Git 历史 | ✅ |

---

## 🔗 相关资源

- [sqlite-zstd](https://github.com/phiresky/sqlite-zstd)
- [ZSTD 压缩库](https://facebook.github.io/zstd/)
- [Git 官方文档](https://git-scm.com/docs)
- [GitLab API](https://docs.gitlab.com/ee/api/)

---

**提案者**: OML Team  
**版本**: 3.0 (优化版)  
**提案日期**: 2026-03-23  
**状态**: 📋 待审批
