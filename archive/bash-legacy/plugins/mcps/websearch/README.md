# WebSearch MCP 插件

**版本**: 1.0.0  
**类型**: MCP 服务  
**提供商**: Exa AI

---

## 📋 概述

WebSearch MCP 插件提供基于 Exa AI 的网络搜索和代码上下文检索功能。

### 功能特性

- ✅ 网络搜索 (`web_search_exa`)
- ✅ 代码上下文检索 (`get_code_context_exa`)
- ✅ 高级搜索 (`web_search_advanced_exa`)
- ✅ 网页抓取 (`crawling_exa`)
- ✅ 本地缓存支持
- ✅ 引用追踪

---

## 🚀 安装

### 自动安装

```bash
# 使用 OML 插件系统
oml plugins install websearch mcp
```

### 手动安装

```bash
# 克隆仓库
cd ~/develop/oh-my-litecode

# 运行安装脚本
bash plugins/mcps/websearch/scripts/post-install.sh
```

---

## 🔧 配置

### 环境变量

```bash
# 设置 Exa API 密钥
export EXA_API_KEY="your-api-key-here"

# 可选配置
export EXA_BASE_URL="https://api.exa.ai"
export EXA_TIMEOUT="30"
```

### 配置文件

创建 `~/.oml/websearch-config.json`:

```json
{
  "exa": {
    "baseUrl": "https://api.exa.ai",
    "timeout": 30,
    "cache": {
      "enabled": true,
      "ttl": 3600,
      "maxSize": 1000
    }
  }
}
```

---

## 📖 使用方法

### 网络搜索

```bash
# 基本搜索
oml mcps websearch search "React hooks tutorial"

# 指定结果数量
oml mcps websearch search "Python async" 20

# 启用自动提示
oml mcps websearch search "TypeScript generics" 10 true
```

### 代码上下文检索

```bash
# 获取代码示例
oml mcps websearch code-context "Go generics syntax"

# 指定 token 数量
oml mcps websearch code-context "Rust async await" 10000
```

### 管理来源

```bash
# 列出缓存的来源
oml mcps websearch sources
```

### 配置管理

```bash
# 查看配置
oml mcps websearch config show

# 设置超时
oml mcps websearch config set EXA_TIMEOUT 60

# 清除缓存
oml mcps websearch config clear-cache
```

---

## 📊 API 参考

### web_search_exa

搜索网络获取相关信息。

**参数**:
- `query` (string): 搜索查询
- `numResults` (number): 结果数量 (默认：10)
- `useAutoprompt` (boolean): 使用自动提示 (默认：true)
- `type` (string): 搜索类型 (`auto`, `fast`, `deep`)

**示例**:
```json
{
  "query": "React hooks tutorial",
  "numResults": 10,
  "useAutoprompt": true,
  "type": "auto"
}
```

### get_code_context_exa

从 GitHub/StackOverflow 获取代码上下文。

**参数**:
- `query` (string): 代码查询
- `tokensNum` (number): 返回的 token 数量 (默认：5000)

**示例**:
```json
{
  "query": "Python async await example",
  "tokensNum": 5000
}
```

---

## 🗄️ 缓存

### 缓存位置

```
~/.oml/cache/websearch/
```

### 缓存策略

- **TTL**: 3600 秒 (1 小时)
- **最大大小**: 1000 个结果
- **自动清理**: 超出 TTL 后自动过期

### 管理缓存

```bash
# 清除缓存
oml mcps websearch config clear-cache

# 查看缓存状态
ls -la ~/.oml/cache/websearch/
```

---

## ⚠️ 故障排查

### 问题 1: API 密钥未配置

**症状**:
```
[ERROR] EXA_API_KEY not set
{"error": "EXA_API_KEY not configured"}
```

**解决方案**:
```bash
export EXA_API_KEY="your-api-key"
```

### 问题 2: 请求超时

**症状**:
```
curl: (28) Operation timed out
```

**解决方案**:
```bash
# 增加超时时间
export EXA_TIMEOUT="60"
```

### 问题 3: 缓存目录权限

**症状**:
```
mkdir: cannot create directory: Permission denied
```

**解决方案**:
```bash
chmod 755 ~/.oml/cache
```

---

## 🔗 相关文档

- [Librarian Subagent](../../subagents/librarian/) - 集成 WebSearch 的子代理
- [Exa AI 文档](https://docs.exa.ai/) - Exa API 完整文档
- [OML MCP 指南](../../docs/mcp/) - MCP 服务使用指南

---

## 📝 更新日志

### 1.0.0 (2026-03-23)

- ✅ 初始版本
- ✅ 网络搜索功能
- ✅ 代码上下文检索
- ✅ 缓存支持
- ✅ 引用追踪

---

**维护者**: OML Team  
**许可**: MIT License
