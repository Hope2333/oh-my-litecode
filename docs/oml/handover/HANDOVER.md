# 任务交接文档

> 从调试机同步 - 2026-02-23

## 当前状态速览

### 可用的包
```bash
# bun - 可用
pacman -U bun-1.2.20-1-aarch64.pkg.tar.xz

# opencode - 可用（但 runtime 版本不匹配）
pacman -U opencode-1.2.10-1-aarch64.pkg.tar.xz
```

### 关键问题

**OpenCode Runtime 版本不匹配**：
- 源码版本：1.2.10
- Runtime 版本：1.1.65（来自旧项目 NDK 编译）
- 表现：`opencode --version` 返回 1.1.65 而非 1.2.10

---

## 文件结构

### bun-termux
```
bun-termux/
├── packaging/pacman/
│   ├── PKGBUILD              # ✅ 可用
│   └── bun-*.pkg.tar.xz      # ✅ 已生成
├── scripts/                   # ⚠️ 未使用，可删除
└── .github/workflows/build.yml  # ⚠️ 需重写
```

### opencode-termux
```
opencode-termux/
├── packaging/pacman/
│   ├── PKGBUILD              # ⚠️ 硬编码引用旧项目路径
│   └── opencode-*.pkg.tar.xz # ⚠️ runtime 版本不匹配
├── scripts/                   # ⚠️ 未使用，可删除
├── sources/opencode/repo/     # 1.2.10 源码
└── .github/workflows/build.yml  # ⚠️ 需重写
```

---

## 需要修改的文件

### 1. opencode-termux/packaging/pacman/PKGBUILD

**当前问题**：硬编码了旧项目路径

**需要改为**：
- 从某个可访问的 URL 下载 NDK runtime
- 或在 GitHub Actions 中预先构建

### 2. GitHub Actions Workflows

**建议结构**：
```yaml
build:
  runs-on: ubuntu-latest
  container: ghcr.io/termux/package-builder:latest
  steps:
    - uses: actions/checkout@v4
    
    - name: Build with makepkg
      run: |
        cd packaging/pacman
        makepkg -f --noconfirm
        
    - uses: actions/upload-artifact@v4
      with:
        path: packaging/pacman/*.pkg.tar.xz
```

---

## OpenCode Runtime 问题详解

**为什么需要 NDK 版本**：
- Termux 是 Android 环境
- 标准 Linux 二进制使用 `/lib/ld-linux-aarch64.so.1`
- Android 使用 `/system/bin/linker64`
- glibc-runner 可以运行 glibc 二进制，但 OpenCode runtime 有问题

**验证方法**：
```bash
file /data/data/com.termux/files/usr/lib/opencode/runtime/opencode
# 正确输出应包含: interpreter /system/bin/linker64
# 错误输出: interpreter /lib/ld-linux-aarch64.so.1
```

---

## 快速验证命令

```bash
# 检查包是否安装
pacman -Q bun opencode

# 测试 bun
bun --version  # 应返回 1.2.20

# 测试 opencode
opencode --version  # 当前返回 1.1.65（runtime版本）

# 检查 runtime 类型
file /data/data/com.termux/files/usr/lib/opencode/runtime/opencode
```
