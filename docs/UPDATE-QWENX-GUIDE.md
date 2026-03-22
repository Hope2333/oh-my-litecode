# qwenx 更新到 OML 指南

**更新日期**: 2026-03-23  
**适用系统**: Termux (Android)  
**OML 版本**: 0.8.0+

---

## 📋 概述

本指南介绍如何将现有的 qwenx 安装更新到最新的 OML (Oh-My-Litecode) 插件系统。

### 更新内容

- ✅ Session 管理系统
- ✅ Hooks 自动化引擎
- ✅ Worker 池并行执行
- ✅ 完整插件系统 (10+ 插件)
- ✅ MCP 服务增强
- ✅ 向后兼容性保证

---

## 🚀 快速更新（推荐）

### 方法一：自动更新脚本

```bash
# 1. 运行更新脚本
bash ~/develop/oh-my-litecode/scripts/update-qwenx.sh

# 2. 验证更新
qwenx --oml-help
qwenx --oml-version
```

### 方法二：手动更新

```bash
# 1. 设置环境变量
export OML_ROOT="$HOME/develop/oh-my-litecode"

# 2. 备份现有配置
cp -r ~/.local/home/qwenx ~/.local/home/qwenx.backup.$(date +%Y%m%d)

# 3. 更新 qwenx 命令
cat > /data/data/com.termux/files/usr/bin/qwenx << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
OML_ROOT="${OML_ROOT:-/data/data/com.termux/files/home/develop/oh-my-litecode}"
export _FAKEHOME="${HOME}/.local/home/qwenx"
[[ "${HOME}" != "${_FAKEHOME}" ]] && export HOME="${_FAKEHOME}"
exec "${OML_ROOT}/oml" qwen "$@"
EOF
chmod +x /data/data/com.termux/files/usr/bin/qwenx

# 4. 验证
qwenx --oml-help
```

---

## 📁 更新步骤详解

### 步骤 1: 检查前置条件

```bash
# 确认 OML 已安装
ls -la ~/develop/oh-my-litecode/oml

# 确认 qwenx 存在
which qwenx

# 检查当前版本
qwenx --help 2>&1 | head -5
```

### 步骤 2: 备份配置

```bash
# 备份整个配置目录
cp -r ~/.local/home/qwenx ~/.local/home/qwenx.backup.$(date +%Y%m%d_%H%M%S)

# 验证备份
ls -la ~/.local/home/qwenx.backup.*
```

### 步骤 3: 运行更新

```bash
# 使用自动更新脚本
bash ~/develop/oh-my-litecode/scripts/update-qwenx.sh
```

### 步骤 4: 验证更新

```bash
# 测试基本功能
qwenx --oml-help
qwenx --oml-version

# 测试插件系统
oml plugins list

# 测试健康检查
oml platform doctor
```

---

## 🔧 新功能使用

### Session 管理

```bash
# 创建会话
oml session create "我的项目"

# 查看会话
oml session current

# 列出会话
oml session list

# 搜索会话
oml session search "关键词"
```

### Worker 池

```bash
# 初始化 Worker 池
oml pool init --min 2 --max 10

# 提交任务
oml worker spawn qwen --task "分析项目结构"

# 查看状态
oml worker status

# 等待完成
oml worker wait
```

### Hooks 系统

```bash
# 初始化 Hooks
oml hooks init

# 注册 Hook
oml hooks add pre build:start ~/scripts/pre-build.sh 10

# 触发 Hook
oml hooks trigger build:start

# 查看状态
oml hooks status
```

### 插件管理

```bash
# 列出插件
oml plugins list

# 查看插件信息
oml plugins info qwen

# 启用插件
oml plugins enable qwen

# 创建插件模板
oml plugins create my-agent agent
```

---

## ⚠️ 常见问题

### Q1: 更新后 qwenx 命令找不到

**解决方案**:
```bash
# 检查 PATH
echo $PATH | grep usr/bin

# 重新创建符号链接
ln -sf ~/develop/oh-my-litecode/oml /data/data/com.termux/files/usr/bin/qwenx
```

### Q2: OML_ROOT 环境变量问题

**解决方案**:
```bash
# 设置环境变量
export OML_ROOT="$HOME/develop/oh-my-litecode"
echo 'export OML_ROOT="$HOME/develop/oh-my-litecode"' >> ~/.bashrc
source ~/.bashrc
```

### Q3: 配置目录权限问题

**解决方案**:
```bash
# 修复权限
chmod -R 700 ~/.local/home/qwenx
chown -R $(whoami) ~/.local/home/qwenx
```

### Q4: 插件加载失败

**解决方案**:
```bash
# 检查插件目录
ls -la ~/develop/oh-my-litecode/plugins/

# 重新初始化
oml plugins list
```

---

## 📊 更新前后对比

| 功能 | 更新前 | 更新后 |
|------|-------|-------|
| **Session 管理** | ❌ | ✅ 完整支持 |
| **Hooks 系统** | ❌ | ✅ 完整支持 |
| **Worker 池** | ❌ | ✅ 完整支持 |
| **插件数量** | 1 | 10+ |
| **MCP 服务** | 3 | 5+ |
| **代码行数** | ~800 | ~25,000+ |
| **测试覆盖** | 无 | 100% (292 测试) |

---

## 🔙 回滚指南

如需回滚到更新前状态：

```bash
# 1. 恢复配置
rm -rf ~/.local/home/qwenx
mv ~/.local/home/qwenx.backup.YYYYMMDD_HHMMSS ~/.local/home/qwenx

# 2. 恢复 qwenx 命令
cp /data/data/com.termux/files/usr/bin/qwenx.backup.* /data/data/com.termux/files/usr/bin/qwenx
chmod +x /data/data/com.termux/files/usr/bin/qwenx

# 3. 验证回滚
qwenx --help
```

---

## 📚 相关文档

- [快速开始](../../../blob/main/QUICKSTART.md)
- [完整使用指南](../../../blob/main/docs/USER-GUIDE.md)
- [架构概览](../../../blob/main/docs/oml/ARCHITECTURE-OVERVIEW.md)
- [部署指南](../../../blob/main/docs/oml/DEPLOYMENT-GUIDE.md)

---

## 🆘 获取帮助

- **GitHub Issues**: https://github.com/your-org/oh-my-litecode/issues
- **讨论区**: https://github.com/your-org/oh-my-litecode/discussions
- **更新脚本**: `bash ~/develop/oh-my-litecode/scripts/update-qwenx.sh`

---

**维护者**: OML Team  
**许可**: MIT License
