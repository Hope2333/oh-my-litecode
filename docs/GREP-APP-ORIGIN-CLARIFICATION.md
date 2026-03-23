# grep-app MCP 来源澄清

**更新日期**: 2026-03-23  
**目的**: 澄清 grep-app MCP 的来源和实验室版关系

---

## 📋 澄清要点

### 实验室版 qwenx **未使用** grep-app MCP

**实验室版** (`archive/legacy-qwenx/`) 的 MCP 配置：

```json
{
  "mcpServers": {
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp@latest"]
    },
    "websearch": {
      "httpUrl": "https://mcp.exa.ai/mcp?tools=web_search_exa"
    }
  }
}
```

**仅包含**:
- ✅ Context7 MCP (文档查询)
- ✅ WebSearch MCP (Exa 网络搜索)

**不包含**:
- ❌ grep-app MCP
- ❌ 本地代码搜索功能

---

## 🔍 grep-app MCP 来源

### 外部参考项目

**项目名称**: `ai-tools-all/grep_app_mcp`

**仓库**: https://github.com/ai-tools-all/grep_app_mcp

**特点**:
- 基于 **grep.app API** (远程服务)
- TypeScript + fastmcp 框架
- 搜索 GitHub 公共仓库
- 需要网络连接

**MCP 工具**:
- `search_code` - 搜索 GitHub 代码
- `get_file` - 获取文件内容
- `batch_get_files` - 批量获取文件

---

### OML 自主实现

**实现时间**: 2026-03-22 ~ 2026-03-23

**实现方式**: **自主开发**，参考了 grep.app 的功能理念

**技术栈**:
- Python + MCP SDK
- GNU grep 后端 (本地)
- 无需外部 API

**MCP 工具**:
- `grep_search_intent` - 自然语言搜索
- `grep_regex` - 正则搜索
- `grep_count` - 统计
- `grep_files_with_matches` - 列出文件

---

## 📊 对比表

| 特征 | ai-tools-all/grep_app_mcp | OML grep-app |
|------|--------------------------|--------------|
| **搜索范围** | GitHub 公共仓库 | 本地代码库 |
| **后端** | grep.app API | GNU grep |
| **网络需求** | ✅ 必需 | ❌ 离线可用 |
| **隐私** | ⚠️ 代码查询发送到外部 | ✅ 本地处理 |
| **API 依赖** | ✅ grep.app API | ❌ 无 |
| **实现语言** | TypeScript | Python |
| **框架** | fastmcp | MCP SDK |

---

## ✅ 澄清结论

### 实验室版 qwenx

**未使用** grep-app MCP，仅使用：
- Context7 MCP
- WebSearch MCP (Exa)

### OML grep-app MCP

**自主实现**，特点：
- 参考了 grep.app 的功能理念
- 使用本地 GNU grep 后端
- 无需外部 API
- 完全离线工作
- 隐私安全

### 与 ai-tools-all/grep_app_mcp 的关系

**参考关系**，非直接使用：
- 参考了功能设计
- 参考了 MCP 工具命名
- **未使用**其代码
- **未使用**其 API
- **自主实现**核心逻辑

---

## 📝 文档更新历史

| 日期 | 更新内容 |
|------|---------|
| 2026-03-23 | 澄清实验室版未使用 grep-app |
| 2026-03-23 | 说明 OML 自主实现来源 |
| 2026-03-23 | 添加对比表 |

---

## 🔗 相关文档

- [grep-app 评估报告](GREP-APP-EVALUATION.md)
- [grep-app 一致性检查](GREP-APP-CONSISTENCY-CHECK.md)
- [Archive 清单](archive/ARCHIVE-MANIFEST.md)
- [实验室版配置](archive/legacy-qwenx/example.settings.json)

---

**维护者**: OML Team  
**更新日期**: 2026-03-23  
**状态**: ✅ 已澄清
