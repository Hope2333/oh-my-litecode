# 构建会话总结 - 2026-02-23

> 从调试机同步

## 概述

本次会话目标：将 `termux.opencode.all` 的构建经验合并到 `bun-termux` 和 `opencode-termux` 两个独立仓库。

## 当前成果

### 包构建状态

| 项目 | 包名 | 版本 | 大小 | 状态 |
|------|------|------|------|------|
| bun-termux | `bun` | 1.2.20-1 | 23MB | ✅ 可用 |
| opencode-termux | `opencode` | 1.2.10-1 | 111MB | ⚠️ 部分可用 |

---

## 已解决的问题

### 1. makepkg 构建流程
- ✅ 正确使用 `makepkg` 而非脚本构建
- ✅ PKGBUILD 结构正确：`prepare()` → `build()` → `package()`
- ✅ 包名从 `bun-termux`/`opencode-termux` 改为 `bun`/`opencode`

### 2. 架构问题
- ✅ Termux 使用 `aarch64` 而非 `arm64`
- ✅ Launcher shebang 使用 `/data/data/com.termux/files/usr/bin/bash`

### 3. bun 构建
- ✅ 从 GitHub releases 下载 glibc 二进制
- ✅ 通过 `grun` (glibc-runner) 运行
- ✅ 测试通过：`bun --version` 返回 1.2.20

---

## 未解决/遗留问题

### 1. OpenCode Runtime 问题 (关键)

**问题描述**：
- GitHub releases 只提供 glibc 版本 (`/lib/ld-linux-aarch64.so.1`)
- Termux 需要 NDK 版本 (`/system/bin/linker64`)

**临时方案**：
- 当前 PKGBUILD 硬编码引用 `termux.opencode.all` 中的 NDK runtime
- 版本固定在 1.1.65（NDK runtime 版本），而非 1.2.10（源码版本）

**需要的解决方案**：
1. 找到 OpenCode NDK 版本的发布源
2. 或自己编译 NDK 版本
3. 或使用交叉编译工具链

### 2. GitHub Actions Workflows (需重写)

**当前状态**：
- 使用脚本式构建，未使用 makepkg
- 无法获取 NDK runtime

### 3. scripts 目录 (冗余)

创建了 `scripts/` 目录但实际使用 `makepkg` 构建，这些脚本未被使用。

---

## 下一步行动

### 优先级 P0 (必须)
1. 解决 OpenCode NDK runtime 来源问题
2. 重写 GitHub Actions 使用 makepkg

### 优先级 P1 (重要)
1. 清理冗余的 scripts 目录
2. 测试 DEB 包构建

### 优先级 P2 (可选)
1. ARM32 支持
2. 自动化版本更新
