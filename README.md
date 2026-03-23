# Oh-My-Litecode (OML)

**Version: 0.1.0-alpha**

A unified toolchain manager for cross-platform AI-assisted development environments on Termux/Android.

## Overview

OML serves as an orchestrator for multiple sub-projects, providing:
- Unified hotfix and patch management
- Cross-platform package building (pacman/dpkg)
- Version migration and upgrade automation
- Documentation hub for all sub-projects

## Sub-Projects

| Project | Description | Status |
|---------|-------------|--------|
| `solve-android/opencode` | OpenCode for Termux with TTY/lock cleanup | Active |
| `solve-android/bun` | Bun runtime for Termux (glibc-runner) | Active |
| `oml-tools` | External tools contract + MCP gateway (cross-client) | Active |

## Quick Start

```bash
# Show available commands
./oml --help

# Unified builds (Termux first, GNU/Linux second)
./oml build --project opencode --target termux-dpkg --ver 1.2.10
./oml build --project opencode --target termux-pacman --ver 1.2.10
./oml build --project opencode --target gnu-debian --ver 1.2.10
./oml build --project opencode --target gnu-arch --ver 1.2.10

# bun-termux is currently Termux-only
./oml build --project bun --target termux-pacman --ver 1.3.9

# Apply hotfixes
./oml hotfix apply <fix-name>

# View documentation
./oml doc <project> <topic>

# Manage opencode-termux integration
./oml opencode diagnose
./oml opencode migrate-installed
./oml opencode plugin list
./oml opencode plugin latest
./oml opencode plugin build --plugin mystatus --odir ~/oct-plugin-out
./oml opencode plugin install
./oml opencode skill list
./oml opencode matrix --vers "1.2.9 1.2.10" --odir ~/oct-out/deb
./oml opencode plugin-build --plugin qwen-oauth-gd --odir ~/oct-plugin-out
```

Plugin safety default (Termux):

- prefer `file://` plugin entries in `~/.config/opencode/opencode.json`
- avoid named plugin entries when plugin has native/postinstall-heavy dependencies

## Environment Policy

- OML is **not Termux-only**.
- Execution priority:
  1. **Termux** as first-class citizen (primary validation path)
  2. **GNU/Linux** as secondary supported environment
- No other OS targets are considered unless explicitly required.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Upstream Projects

- [OpenCode](https://github.com/anomalyco/opencode) - MIT License
- [Bun](https://github.com/oven-sh/bun) - MIT License
- [bun-termux-loader](https://github.com/kaan-escober/bun-termux-loader) - MIT License

---

## 📁 Archive

本仓库包含历史版本存档于 `archive/` 目录：

- **[archive/legacy-qwenx/](archive/legacy-qwenx/)** - 实验室版 qwenx (已废弃)
  - **状态**: ❌ 已废弃，不推荐新开发
  - **用途**: 历史参考、迁移指南
  - **推荐**: 使用 [0.1.0](https://github.com/Hope2333/oh-my-litecode/releases/tag/0.1.0) 版本
  - **详情**: [archive/ARCHIVE-MANIFEST.md](archive/ARCHIVE-MANIFEST.md)

---

## 🏷️ 版本标签

| 版本 | 语言 | 状态 | 推荐 |
|------|------|------|------|
| **[0.1.0](https://github.com/Hope2333/oh-my-litecode/releases/tag/0.1.0)** | TS + Py + Bash | ✅ 当前 | ⭐⭐⭐⭐⭐ |
| **[0.1.0-bash](https://github.com/Hope2333/oh-my-litecode/releases/tag/0.1.0-bash)** | 100% Bash | ✅ 保留 | ⭐⭐⭐ |
| **legacy-qwenx** | 100% Bash | ❌ 废弃 | ❌ |

**详情**: [docs/TAGS.md](docs/TAGS.md)
