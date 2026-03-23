# OML 最佳实践手册

**版本**: 0.2.0  
**日期**: 2026-03-23

---

## 📖 概述

本手册收集 OML 使用的最佳实践。

---

## 🎯 安装最佳实践

### 1. 选择安装路径

```bash
# 推荐路径
export OML_ROOT="${HOME}/develop/oh-my-litecode"

# 避免使用系统目录
# 不要使用：/usr/local, /opt (需要 root)
```

### 2. 设置 PATH

```bash
# 添加到 ~/.bashrc 或 ~/.zshrc
export PATH="${OML_ROOT}:$PATH"

# 使配置生效
source ~/.bashrc
```

### 3. 验证安装

```bash
# 检查版本
oml --help

# 运行版本检查
./scripts/verify-version.sh
```

---

## 🔌 插件管理最佳实践

### 1. 插件命名

```json
{
  "name": "my-plugin",      // 小写，连字符分隔
  "version": "0.2.0",       // 与 OML 版本一致
  "type": "mcp"             // 明确类型
}
```

### 2. 插件安全

```bash
# 检查插件权限
ls -la plugins/mcps/<name>/

# 验证 plugin.json
jq . plugins/mcps/<name>/plugin.json

# 运行测试
bash plugins/mcps/<name>/tests/test-plugin.sh
```

### 3. 插件更新

```bash
# 批量更新插件
oml plugins update all

# 单个插件更新
oml plugins update <name>

# 回滚到旧版本
oml plugins rollback <name>
```

---

## 🚀 性能优化最佳实践

### 1. 缓存配置

```bash
# 设置缓存大小
export MAX_SIZE=1000

# 设置 TTL
export TTL=3600

# 清理过期缓存
oml cache cleanup
```

### 2. 启动优化

```bash
# 启用懒加载
export OML_LAZY_LOAD=1

# 预编译脚本
for f in modules/*.sh; do
    bash -n "$f"
done
```

### 3. 内存管理

```bash
# 监控内存使用
oml perf monitor status

# 清理内存
unset OML_DEBUG
```

---

## 🔒 安全最佳实践

### 1. API Key 管理

```bash
# 使用 Key Switcher
oml qwen-key add sk-xxxxx work

# 不要硬编码密钥
# ❌ export QWEN_API_KEY="sk-xxxxx"
# ✅ om l qwen-key use 0
```

### 2. OAuth 管理

```bash
# 使用 OAuth Switcher
oml qwen-oauth add work

# 定期更新凭证
oml qwen-oauth refresh
```

### 3. 权限控制

```bash
# 设置文件权限
chmod 700 ~/.oml/
chmod 600 ~/.oml/*.json

# 检查权限
ls -la ~/.oml/
```

---

## 📦 备份最佳实践

### 1. 自动备份

```bash
# 启用自动备份
oml backup start

# 配置备份间隔
# 编辑 ~/.oml/backup-config.json
```

### 2. 手动备份

```bash
# 运行备份
oml backup run

# 查看备份
ls -la ~/.oml/backups/
```

### 3. 恢复备份

```bash
# 列出备份
oml backup status

# 恢复备份
oml backup restore backup-20260323_120000.tar.gz
```

---

## 🔄 云同步最佳实践

### 1. 初次同步

```bash
# 初始化
oml cloud init

# 认证
oml cloud auth

# 拉取
oml cloud sync pull
```

### 2. 日常同步

```bash
# 手动同步
oml cloud sync push
oml cloud sync pull

# 或启用自动同步
# 编辑 ~/.oml/sync-config.json
# "auto_sync": true
```

### 3. 冲突解决

```bash
# 查看冲突
ls ~/.oml/conflicts/

# 手动解决
# 编辑冲突文件，保留需要的内容
```

---

## 📊 监控最佳实践

### 1. 性能监控

```bash
# 启动监控
oml perf monitor start

# 查看状态
oml perf monitor status

# 生成报告
oml perf monitor report
```

### 2. 错误监控

```bash
# 报告错误
oml error report "Description"

# 查看错误
oml error list
```

### 3. 日志管理

```bash
# 查看日志
cat ~/.oml/errors.log
cat ~/.oml/perf.log

# 清理旧日志
find ~/.oml -name "*.log" -mtime +7 -delete
```

---

## 🎯 开发最佳实践

### 1. 代码规范

```bash
# 所有脚本使用 set -euo pipefail
set -euo pipefail

# 变量加引号
echo "$variable"

# 函数命名规范
cmd_example() { ... }
show_help() { ... }
```

### 2. 测试规范

```bash
# 每个插件都要有测试
plugins/mcps/<name>/tests/test-plugin.sh

# 测试覆盖率 >80%
bash plugins/mcps/<name>/tests/test-plugin.sh
```

### 3. 文档规范

```bash
# 每个插件都要有 help
oml mcp <name> help

# 文档完整
# - plugin.json
# - main.sh 注释
# - 测试用例
```

---

## 📚 相关文档

- [API 参考](../api/API-REFERENCE.md)
- [插件开发指南](PLUGIN-DEV-GUIDE.md)
- [故障排查](TROUBLESHOOTING.md)

---

**维护者**: OML Team  
**版本**: 0.2.0
