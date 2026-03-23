# OML 版本管理规范

**版本**: 0.2.0 (固定)  
**生效日期**: 2026-03-23  
**状态**: ✅ 强制执行

---

## 📋 版本号规则

### 当前版本

**OML 核心版本**: `0.2.0` (固定，禁止飘移)

### 版本格式

```
<major>.<minor>.<patch>
  │       │       │
  │       │       └─ 补丁版本 (Bug 修复)
  │       └─ 次要版本 (向后兼容的功能新增)
  └─ 主版本 (不兼容的 API 修改)
```

### 版本范围

| 版本 | 状态 | 说明 |
|------|------|------|
| **0.1.x** | ❌ 已废弃 | 初始 alpha 版本 |
| **0.2.0** | ✅ 当前 | 固定版本 (禁止飘移) |
| **0.3.0** | 📋 计划 | 下一版本 (需审批) |

---

## 🚫 禁止飘移规则

### 核心规则

1. **OML 核心版本固定为 0.2.0**
   - 除非经过团队审批，否则禁止修改
   - 所有功能实现在 0.2.0 框架内进行

2. **插件版本统一为 0.2.0**
   - 所有 `plugins/*/plugin.json` 必须是 `"version": "0.2.0"`
   - 禁止使用 `0.2.1`, `0.2.2` 等飘移版本

3. **文档版本引用**
   - 文档中引用版本时必须使用 `0.2.0`
   - 历史版本文档放入 `docs/archive/`

### 例外情况

以下情况允许版本变更：

1. **紧急 Bug 修复**: `0.2.1` (需团队审批)
2. **安全补丁**: `0.2.1` (需团队审批)
3. **新版本发布**: `0.3.0` (需团队审批)

---

## 📝 版本标记位置

### 必须统一标记的文件

| 文件 | 标记格式 | 当前值 |
|------|---------|--------|
| `oml` | `OML_VERSION="0.2.0"` | ✅ |
| `plugins/*/plugin.json` | `"version": "0.2.0"` | ✅ |
| `README.md` | `Version: 0.2.0` | ✅ |
| `README-OML.md` | `**版本**: 0.2.0` | ✅ |
| `QUICKSTART.md` | `**版本**: 0.2.0` | ✅ |

### 检查命令

```bash
# 检查核心版本
grep 'OML_VERSION=' oml

# 检查插件版本
find plugins/ -name "plugin.json" -exec grep '"version"' {} \;

# 检查文档版本
grep -r "版本.*0\.[0-9]" docs/*.md README*.md
```

---

## 🔧 版本管理流程

### 版本变更流程

```
提议 → 讨论 → 审批 → 实施 → 验证
```

### 变更要求

1. **提议**: 在 GitHub Issues 提出版本变更
2. **讨论**: 团队讨论变更必要性
3. **审批**: 核心团队审批通过
4. **实施**: 统一修改所有版本标记
5. **验证**: 运行版本检查脚本

### 验证脚本

```bash
#!/usr/bin/env bash
# scripts/verify-version.sh

echo "Checking OML version consistency..."

# Check core version
core_version=$(grep 'OML_VERSION=' oml | cut -d'"' -f2)
echo "Core version: $core_version"

# Check plugin versions
plugin_count=$(find plugins/ -name "plugin.json" | wc -l)
plugin_versions=$(find plugins/ -name "plugin.json" -exec grep '"version"' {} \; | cut -d'"' -f4 | sort -u)
echo "Plugin versions: $plugin_versions (count: $plugin_count)"

# Verify consistency
if [[ "$core_version" == "0.2.0" ]] && [[ "$plugin_versions" == "0.2.0" ]]; then
    echo "✓ Version consistency check passed"
    exit 0
else
    echo "✗ Version inconsistency detected"
    exit 1
fi
```

---

## 📊 版本历史

### 0.2.0 (当前)

**发布日期**: 2026-03-23  
**状态**: 固定版本  
**特性**:
- ✅ 统一安装/更新入口
- ✅ Qwenx 部署 (Android 权限检测)
- ✅ SuperTUI 交互界面
- ✅ 云同步框架
- ✅ 性能优化工具
- ✅ Filesystem MCP
- ✅ Git MCP

### 0.1.0-alpha (已废弃)

**发布日期**: 2026-02-18  
**状态**: 已废弃  
**说明**: 初始 alpha 版本，已统一升级到 0.2.0

---

## 🎯 未来版本规划

### 0.3.0 (计划中)

**预计**: 2026-04  
**特性**:
- [ ] MCP 服务 10+
- [ ] Subagents 8+
- [ ] Skills 5+
- [ ] 云同步完整实现
- [ ] 性能优化完成

### 0.4.0 (规划)

**预计**: 2026-05  
**特性**:
- [ ] Skills 系统完善
- [ ] SuperTUI 2.0
- [ ] 插件市场 alpha

### 1.0.0 (长期目标)

**预计**: 2026-Q4  
**特性**:
- [ ] 正式版发布
- [ ] 完整文档
- [ ] 生态系统

---

## ✅ 检查清单

### 版本一致性检查

- [ ] `oml` 脚本：`OML_VERSION="0.2.0"`
- [ ] 所有 `plugin.json`: `"version": "0.2.0"`
- [ ] `README.md`: `Version: 0.2.0`
- [ ] `README-OML.md`: `**版本**: 0.2.0`
- [ ] `QUICKSTART.md`: `**版本**: 0.2.0`
- [ ] 其他文档：引用 `0.2.0`

### 禁止项检查

- [ ] 无 `0.2.1`, `0.2.2` 等飘移版本
- [ ] 无 `0.3.0` 等未审批版本
- [ ] 无 `alpha`, `beta` 等临时标记

---

## 🔗 相关文档

- [实施进度](IMPLEMENTATION-PROGRESS.md)
- [完整总结](COMPLETE-IMPLEMENTATION-SUMMARY.md)
- [变更日志](CHANGELOG.md)

---

**维护者**: OML Team  
**版本**: 0.2.0 (固定)  
**生效日期**: 2026-03-23  
**下次审查**: 2026-04-01
