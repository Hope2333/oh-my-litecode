# OML 版本标签 (Tags)

**更新日期**: 2026-03-23

---

## 📋 版本标签列表

### 0.1.0-bash (Bash 完整版)

**提交**: `5b80f75`  
**日期**: 2026-03-23  
**状态**: ✅ 保留 (不推荐新开发)

#### 特性

- ✅ 完整插件系统 (10+ 插件)
- ✅ Session 管理系统 (6 模块)
- ✅ Worker 池并行执行 (5 模块)
- ✅ Hooks 自动化引擎 (4 模块)
- ✅ 100% 测试覆盖 (292 测试)
- ✅ 完整文档 (30+ 文档)

#### 代码统计

| 项目 | 数值 |
|------|------|
| **总代码量** | ~26,000 行 Bash |
| **核心模块** | 18 个 |
| **插件** | 10+ 个 |
| **测试** | 292 个 |

#### 使用方式

```bash
# 检出到此版本
git checkout 0.1.0-bash

# 安装
bash scripts/install-archlinux.sh

# 使用
./oml --help
qwenx "你好"
```

#### 注意事项

⚠️ **此版本已保留但不推荐新开发**

原因:
- 100% Bash，类型不安全
- 跨平台一致性差
- 可维护性低

**推荐**: 迁移到 `0.1.0` (TypeScript/Python 混合版)

---

### 0.1.0 (TypeScript/Python 混合版)

**提交**: `0b04908`  
**日期**: 2026-03-23  
**状态**: ✅ 推荐使用的版本

#### 特性

- ✅ TypeScript CLI 入口
- ✅ Python Hooks 引擎
- ✅ TypeScript Session 管理
- ✅ TypeScript Worker 池
- ✅ TypeScript/Python MCP 服务
- ✅ 向后兼容 Bash 版本

#### 迁移进度

| Phase | 内容 | 状态 |
|-------|------|------|
| **Phase 1** | TypeScript CLI | ✅ 100% |
| **Phase 2** | Hooks 系统 Python | ✅ 100% |
| **Phase 3A** | context7 MCP TypeScript | ✅ 100% |
| **Phase 3B** | grep-app MCP Python | ✅ 100% |
| **Phase 3C** | plan agent Python | ✅ 100% |

#### 代码分布

| 语言 | 代码行数 | 占比 |
|------|---------|------|
| **Bash** | ~26,000 | 79% (保留) |
| **TypeScript** | ~8,000 | 9% |
| **Python** | ~6,000 | 7% |
| **JSON** | ~4,000 | 5% |

#### 测试覆盖

| 类型 | 测试数 | 覆盖率 |
|------|-------|--------|
| **Bash 测试** | 292 | 100% |
| **TypeScript 测试** | ~50 | ~80% |
| **Python 测试** | ~40 | ~85% |

#### 使用方式

```bash
# 检出到此版本
git checkout 0.1.0

# 安装
bash scripts/install-archlinux.sh

# 使用
./oml --help
qwenx "你好"

# 或使用 TypeScript CLI
npm install
npm run dev
```

#### 推荐理由

✅ **这是推荐使用的版本！**

原因:
- 类型安全
- 跨平台一致
- 易于维护
- 向后兼容

---

## 📊 版本对比

| 特征 | 0.1.0-bash | 0.1.0 |
|------|-----------|------|
| **语言** | 100% Bash | TS + Py + Bash |
| **代码量** | ~26,000 行 | ~40,000 行 |
| **类型安全** | ❌ | ✅ |
| **跨平台** | ⚠️ | ✅ |
| **可维护性** | ⚠️ | ✅ |
| **推荐** | ❌ | ✅ |

---

## 🔗 GitHub 链接

### 查看 Tag

- **0.1.0-bash**: https://github.com/Hope2333/oh-my-litecode/releases/tag/0.1.0-bash
- **0.1.0**: https://github.com/Hope2333/oh-my-litecode/releases/tag/0.1.0

### 下载源码

```bash
# 下载 Bash 版
git clone --branch 0.1.0-bash https://github.com/Hope2333/oh-my-litecode.git

# 下载混合版 (推荐)
git clone --branch 0.1.0 https://github.com/Hope2333/oh-my-litecode.git
```

---

## 📚 相关文档

- [项目历史与状态](PROJECT-HISTORY-AND-STATUS.md)
- [迁移指南](MIGRATION-TS-PY.md)
- [部署指南](DEPLOYMENT-GUIDE.md)
- [更新总结](LOCAL-UPDATE-SUMMARY.md)

---

**维护者**: OML Team  
**最后更新**: 2026-03-23
