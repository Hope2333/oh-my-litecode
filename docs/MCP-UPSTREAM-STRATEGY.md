# OML MCP 上游更新策略

**版本**: 1.0
**日期**: 2026-03-23

---

## 📋 原始语言分析

### 当前实现语言

| 插件 | 原始语言 | 行数 | 说明 |
|------|---------|------|------|
| **qwen agent** | Bash | 1,358 | 包装 qwen CLI |
| **context7 MCP** | Bash | 984 | 配置管理 + npx 调用 |
| **grep-app MCP** | Bash | 2,146 | grep/find 包装 |
| **build agent** | Bash | 1,257 | make/pacman 包装 |
| **plan agent** | Bash | 1,737 | 纯逻辑 (部分 Python) |
| **websearch** | Bash | 246 | Exa API 包装 |

**结论**: 所有插件原始实现都是 **Bash**

---

## 🔗 MCP 上游依赖分析

### 1. context7 MCP

#### 上游服务
```
名称：@upstash/context7-mcp
类型：NPM 包
运行方式：npx -y @upstash/context7-mcp@latest
上游仓库：https://github.com/upstash/context7-mcp
更新频率：不定期 (跟随 Context7 API)
```

#### 依赖关系
```
OML context7 插件 (Bash)
    └── 配置管理 (settings.json 编辑)
    └── 模式切换 (local/remote)
    └── 密钥管理 (CONTEXT7_API_KEY)
    └── @upstash/context7-mcp (实际 MCP 服务)
```

#### 上游更新影响

| 更新类型 | 影响 | 应对措施 |
|---------|------|---------|
| **NPM 包版本更新** | 低 | 自动使用最新版 (`@latest`) |
| **MCP 协议变更** | 中 | 更新配置格式 |
| **API 端点变更** | 中 | 更新 remote mode URL |
| **认证方式变更** | 高 | 更新密钥管理逻辑 |

#### 迁移到 TypeScript 的优势

```typescript
// 当前 Bash 实现
enable_local_mode() {
  # 手动编辑 JSON (容易出错)
  python3 -c "
import json
with open('settings.json', 'r') as f:
    config = json.load(f)
config['mcpServers']['context7'] = {...}
with open('settings.json', 'w') as f:
    json.dump(config, f)
"
}

// TypeScript 实现
async function enableLocalMode() {
  const settings = await loadSettings();
  settings.mcpServers.context7 = {
    command: 'npx',
    args: ['-y', '@upstash/context7-mcp@latest'],
    enabled: true,
  };
  await saveSettings(settings);  // 类型安全，自动格式化
}
```

**优势**:
- 使用官方 MCP SDK (`@modelcontextprotocol/sdk`)
- 类型安全的配置管理
- 自动处理上游 API 变更

---

### 2. grep-app MCP

#### 上游服务
```
名称：无 (本地实现)
类型：纯本地逻辑
依赖：GNU grep, GNU find, Python 3
```

#### 依赖关系
```
OML grep-app 插件 (Bash)
    └── grep 命令 (系统依赖)
    └── find 命令 (系统依赖)
    └── Python (部分逻辑)
```

#### 上游更新影响

| 更新类型 | 影响 | 应对措施 |
|---------|------|---------|
| **GNU grep 更新** | 低 | 标准工具，向后兼容 |
| **GNU find 更新** | 低 | 标准工具，向后兼容 |
| **Python 版本更新** | 低 | 支持 Python 3.10+ |

**结论**: 无外部 MCP 上游，迁移到 Python 主要是代码质量提升

---

### 3. websearch MCP

#### 上游服务
```
名称：Exa API
类型：REST API
端点：https://api.exa.ai
认证：API Key (x-api-key)
更新频率：API 版本迭代
```

#### 依赖关系
```
OML websearch 插件 (Bash)
    └── curl (HTTP 客户端)
    └── jq (JSON 处理)
    └── Exa API (外部服务)
```

#### 上游更新影响

| 更新类型 | 影响 | 应对措施 |
|---------|------|---------|
| **API 端点变更** | 高 | 更新 EXA_BASE_URL |
| **认证方式变更** | 高 | 更新密钥管理 |
| **响应格式变更** | 中 | 更新 JSON 解析 |
| **速率限制变更** | 中 | 更新重试逻辑 |

#### 迁移到 Python 的优势

```python
# 当前 Bash 实现
search_web() {
  local query="$1"
  local result
  result=$(curl -s -X POST "$EXA_BASE_URL/search" \
    -H "x-api-key: $EXA_API_KEY" \
    -d "{\"query\": \"$query\"}")
  
  # 手动解析 JSON (容易出错)
  echo "$result" | jq -r '.results[].title'
}

# Python 实现
from exa_py import Exa  # 官方 SDK

async def search_web(query: str) -> list[Result]:
    client = Exa(api_key=os.environ['EXA_API_KEY'])
    response = await client.search(query)
    return response.results  # 类型安全，自动处理 API 变更
```

**优势**:
- 使用官方 SDK (`exa-py`)
- 自动处理 API 版本兼容
- 类型安全的响应解析

---

## 🔄 上游更新应对策略

### 策略 1: 版本锁定 (推荐)

```json
// package.json (TypeScript 插件)
{
  "dependencies": {
    "@upstash/context7-mcp": "1.2.3",  // 锁定版本
    "@modelcontextprotocol/sdk": "^0.5.0"
  }
}
```

```txt
# requirements.txt (Python 插件)
exa-py==1.0.0  # 锁定版本
mcp>=0.5.0
```

**优点**: 可重现，避免意外破坏
**缺点**: 需要手动更新依赖

### 策略 2: 自动更新 + CI 测试

```yaml
# .github/workflows/dependency-update.yml
name: Dependency Update

on:
  schedule:
    - cron: '0 0 * * 0'  # 每周日检查
  
jobs:
  update:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/dependabot@v2
      - run: npm update  # 或 pip install --upgrade
      - run: npm test    # 运行测试验证
```

**优点**: 自动跟进上游
**缺点**: 需要完善的测试覆盖

### 策略 3: 适配层模式

```typescript
// plugins/mcps/context7/src/context7-adapter.ts
// 适配层：隔离上游变更

interface Context7MCP {
  enable(): Promise<void>;
  search(query: string): Promise<Result[]>;
}

class Context7Adapter implements Context7MCP {
  // 如果上游 API 变更，只需修改适配器
  async search(query: string): Promise<Result[]> {
    // v1 API
    // return await this.client.v1.search(query);
    
    // v2 API (上游更新后)
    return await this.client.v2.find(query);
  }
}
```

**优点**: 最小化上游变更影响
**缺点**: 增加代码复杂度

---

## 📊 迁移后上游更新对比

| 场景 | Bash 实现 | TypeScript/Python 实现 |
|------|----------|----------------------|
| **NPM 包更新** | 手动改 npx 参数 | `npm update` + 类型检查 |
| **API 变更** | 手动改 curl/jq | SDK 自动处理 |
| **配置格式变更** | Python 脚本编辑 JSON | 类型安全配置类 |
| **认证变更** | 改 Bash 变量 | 环境变量/密钥管理库 |
| **测试验证** | 手动测试 | 自动化测试 |

---

## ✅ 建议

### context7 MCP (TypeScript)

```bash
# 迁移后处理上游更新
cd plugins/mcps/context7
npm update @upstash/context7-mcp  # 更新上游
npm test                          # 运行测试
git commit -m "chore: update context7-mcp to v1.2.3"
```

### grep-app MCP (Python)

```bash
# 迁移后处理上游更新 (无外部 MCP)
cd plugins/mcps/grep-app
pip install --upgrade grep-find-utils  # 如有工具库
pytest                               # 运行测试
```

### websearch MCP (Python)

```bash
# 迁移后处理上游更新
cd plugins/mcps/websearch
pip install --upgrade exa-py  # 更新官方 SDK
pytest                        # 运行测试
```

---

## 🔗 相关资源

- [MCP SDK (TypeScript)](https://github.com/modelcontextprotocol/typescript-sdk)
- [MCP SDK (Python)](https://github.com/modelcontextprotocol/python-sdk)
- [Exa Python SDK](https://github.com/exa-labs/exa-py)
- [Context7 MCP](https://github.com/upstash/context7-mcp)

---

**维护者**: OML Team
**许可**: MIT License
