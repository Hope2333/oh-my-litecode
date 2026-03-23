# OML 故障排查指南

**版本**: 0.2.0  
**日期**: 2026-03-23

---

## 📖 概述

本指南帮助解决 OML 使用中的常见问题。

---

## 🔍 诊断命令

### 系统信息

```bash
# 查看系统信息
oml update status

# 检查版本一致性
./scripts/verify-version.sh

# 查看 OML 状态
oml --help
```

### 日志查看

```bash
# 查看错误日志
cat ~/.oml/errors.log

# 查看性能日志
cat ~/.oml/perf.log

# 查看同步状态
oml cloud sync status
```

---

## ❌ 常见问题

### 1. 命令找不到

**问题**: `oml: command not found`

**解决方案**:
```bash
# 检查 PATH
echo $PATH | grep oh-my-litecode

# 重新添加 PATH
export PATH="$HOME/develop/oh-my-litecode:$PATH"

# 添加到 ~/.bashrc
echo 'export PATH="$HOME/develop/oh-my-litecode:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### 2. 插件加载失败

**问题**: `Failed to load plugin: <name>`

**解决方案**:
```bash
# 检查插件目录
ls -la plugins/mcps/<name>/

# 检查权限
chmod +x plugins/mcps/<name>/main.sh

# 验证 plugin.json
jq . plugins/mcps/<name>/plugin.json

# 重新安装插件
oml plugins install <name>
```

### 3. 版本不一致

**问题**: `Version mismatch detected`

**解决方案**:
```bash
# 运行版本检查
./scripts/verify-version.sh

# 统一版本
for f in plugins/*/plugin.json; do
    sed -i 's/"version": "[^"]*"/"version": "0.2.0"/g' "$f"
done

# 再次检查
./scripts/verify-version.sh
```

### 4. 云同步失败

**问题**: `Cloud sync failed`

**解决方案**:
```bash
# 检查认证
oml cloud auth

# 查看同步状态
oml cloud sync status

# 清除缓存
rm -rf ~/.oml/sync-queue.json

# 重新同步
oml cloud sync pull
```

### 5. 性能问题

**问题**: 启动慢，命令响应延迟高

**解决方案**:
```bash
# 运行性能基准
oml perf benchmark

# 清除缓存
rm -rf ~/.oml/cache/*

# 优化配置
oml perf optimize

# 查看性能监控
oml perf monitor status
```

### 6. MCP 服务不可用

**问题**: `MCP service unavailable`

**解决方案**:
```bash
# 检查 MCP 状态
oml mcp <name> --help

# 重启 MCP 服务
oml mcp <name> restart

# 检查依赖
which python3 node npm

# 重新安装依赖
pip install mcp pydantic
npm install -g <package>
```

### 7. Subagent 执行失败

**问题**: `Subagent execution failed`

**解决方案**:
```bash
# 检查 Subagent 状态
oml subagent <name> status

# 查看日志
cat ~/.oml/subagent-<name>.log

# 重新初始化
oml subagent <name> init

# 检查依赖
which bash curl
```

---

## 🔧 高级故障排查

### 启用调试模式

```bash
# 设置调试模式
export OML_DEBUG=1

# 运行命令
oml <command> --verbose

# 查看详细日志
cat ~/.oml/debug.log
```

### 安全模式

```bash
# 禁用所有插件
export OML_NO_PLUGINS=1

# 运行基本命令
oml --help

# 逐个启用插件
export OML_PLUGINS=<name>
oml <command>
```

### 恢复出厂设置

```bash
# 备份配置
cp -r ~/.oml ~/.oml.backup

# 清除配置
rm -rf ~/.oml

# 重新初始化
oml install

# 恢复配置
cp ~/.oml.backup/config.json ~/.oml/
```

---

## 📞 获取帮助

### 文档资源

- [API 参考](../api/API-REFERENCE.md)
- [插件开发指南](guides/PLUGIN-DEV-GUIDE.md)
- [最佳实践](BEST-PRACTICES.md)

### 社区支持

- GitHub Issues: 提交 bug 报告
- 社区论坛：提问和讨论
- 文档：查看官方文档

### 错误报告

```bash
# 收集错误信息
oml error report "Description of the issue"

# 查看错误列表
oml error list

# 查看错误详情
oml error show ERR-<id>
```

---

## 📊 诊断清单

### 启动问题

- [ ] 检查 PATH 设置
- [ ] 检查依赖项
- [ ] 检查权限
- [ ] 查看启动日志

### 插件问题

- [ ] 检查插件目录
- [ ] 验证 plugin.json
- [ ] 检查 main.sh
- [ ] 运行测试

### 性能问题

- [ ] 运行基准测试
- [ ] 清除缓存
- [ ] 优化配置
- [ ] 监控资源使用

### 同步问题

- [ ] 检查认证
- [ ] 查看同步状态
- [ ] 清除同步队列
- [ ] 重新同步

---

**维护者**: OML Team  
**版本**: 0.2.0
