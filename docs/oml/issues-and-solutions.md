# OML/OCT 问题跟踪与解决方案

> 整合调试机交接信息 - 2026-02-23

---

## 1. 核心问题

### 1.1 OpenCode NDK Runtime 来源

**问题**：
- OpenCode GitHub releases 只提供 glibc 版本
- glibc 版本使用 `/lib/ld-linux-aarch64.so.1`（Linux）
- Termux/Android 需要 NDK 版本（`/system/bin/linker64`）
- 当前 PKGBUILD 硬编码引用 `termux.opencode.all` 中的预编译 NDK runtime

**影响**：
- 版本不匹配：源码 1.2.10，runtime 1.1.65
- GitHub Actions 无法构建（无法访问本地路径）
- 无法自动更新

**解决方案选项**：

| 方案 | 可行性 | 工作量 | 说明 |
|------|--------|--------|------|
| A. bun build --compile | ⚠️ 有限 | 中 | OpenCode 源码可用 bun 编译，但产物仍是 glibc |
| B. 交叉编译 | ⚠️ 复杂 | 高 | 需要 NDK 工具链，编译 bun + opencode |
| C. 预编译 runtime 托管 | ✅ 可行 | 低 | 将 NDK runtime 托管到 GitHub Releases |
| D. glibc-runner + bun-termux-loader | ✅ 已验证 | 中 | 使用 grun + loader 运行 glibc runtime |

**推荐**：方案 D（已在 OCT 中实现）

---

### 1.2 GitHub Actions 需重写

**当前问题**：
- 使用脚本式构建而非 makepkg
- 无法获取 NDK runtime

**解决方案**：

```yaml
name: Build

on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    container: ghcr.io/termux/package-builder:latest
    steps:
      - uses: actions/checkout@v4

      - name: Build package
        run: |
          cd packaging/pacman
          makepkg -f --noconfirm

      - uses: actions/upload-artifact@v4
        with:
          name: packages
          path: packaging/pacman/*.pkg.tar.*
```

---

### 1.3 scripts 目录冗余

**问题**：
- 调试机创建了 `scripts/` 目录
- 实际使用 `makepkg` 构建，这些脚本未被使用

**解决方案**：
- 删除冗余 scripts 目录
- 或保留作为备用构建方式（非 makepkg）

---

## 2. 版本状态

### 2.1 本机版本

| 项目 | 版本 | runtime | 状态 |
|------|------|---------|------|
| oh-my-litecode | v0.1.0-alpha | - | 母项目 |
| opencode-termux | 1.1.65-8 | bun compiled | ✅ 可用 |
| bun-termux | 1.3.9-1 | glibc + grun | ✅ 可用 |

### 2.2 调试机版本

| 项目 | 版本 | 问题 |
|------|------|------|
| bun-termux | 1.2.20-1 | ✅ 可用 |
| opencode-termux | 1.2.10-1 | ⚠️ runtime 1.1.65 不匹配 |

---

## 3. 技术限制

### 3.1 UPX 不兼容 Bun 可执行文件

**原因**：
- Bun `--compile` 产物使用 `---- Bun! ----` 标记定位嵌入数据
- loader 包装后添加 `BUNWRAP1` 元数据标记
- UPX 压缩会破坏这些标记的位置和结构

**解决方案**：使用 `strip` + `zstd/xz` 分发压缩

### 3.2 opencode web 无内置 HTTPS

**原因**：`Bun.serve()` 在 OpenCode 中未暴露 cert/key 选项

**解决方案**：
- 反向代理（Caddy / Nginx）
- Cloudflare Tunnel
- 修改源码支持 TLS

---

## 4. 下一步行动

### P0 - 必须完成

1. **同步调试机最新更改** - 调试机有更新的 PKGBUILD 和项目结构
2. **统一版本** - 确定最终 runtime 策略
3. **重写 GitHub Actions** - 使用 makepkg

### P1 - 重要

1. 删除冗余 scripts 目录
2. 测试 DEB 包构建
3. 完善文档

### P2 - 可选

1. ARM32 支持
2. 自动化版本检测和更新

---

## 5. 参考链接

- [SESSION_SUMMARY.md](./handover/SESSION_SUMMARY.md)
- [HANDOVER.md](./handover/HANDOVER.md)
- [packaging-standards.md](./packaging-standards.md)
- [build-rules.md](./build-rules.md)
