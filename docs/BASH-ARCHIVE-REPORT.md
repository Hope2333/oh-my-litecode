# Bash 归档报告

**Date**: 2026-04-01  
**Version**: v0.2.2-c

---

## 归档统计

| 类别 | 文件数 | 状态 |
|------|--------|------|
| Core Modules | 19 | 已归档 |
| Plugins | 124 | 已归档 |
| Tools | 16 | 已归档 |
| Tests & Benchmarks | 9 | 已归档 |
| Hotfix | 1 | 已归档 |
| **总计** | **169** | 已归档 |

---

## 归档位置

```
archive/bash-legacy/
├── core-phase2/      # Core modules (7 files)
├── modules-phase2/   # Modules (7 files)
├── plugins/          # All plugins (124 files)
├── tests-benchmarks/ # Tests and benchmarks (9 files)
├── tools/            # Tools (16 files)
└── hotfix/           # Hotfix (1 file)
```

---

## 迁移状态

| 插件类型 | Bash 文件 | TypeScript 文件 | 迁移率 |
|----------|-----------|-----------------|--------|
| Agents | 5 | 3 | 60% |
| Subagents | 39 | 12 | 31% |
| MCPs | 27 | 8 | 30% |
| Skills | 20 | 17 | 85% |
| **总计** | **91** | **40** | **44%** |

---

## 保留的 Bash 文件

以下 Bash 文件暂时保留（未迁移）：

- solve-android/ 目录下的 Android 特定脚本
- 部分插件的包装脚本（main.sh）

---

## 空间节省

归档前 Bash 文件大小：~5MB  
归档后 Bash 文件大小：~5MB（压缩归档）  
TypeScript 文件大小：~2MB

---

## 恢复方法

如需恢复归档的 Bash 文件：

```bash
# 从 git 历史恢复
git checkout v0.2.1-bashoff -- core/ modules/ plugins/
```

---

**注意**: 归档文件可通过 git 历史随时恢复。
