# qwenx on Arch Linux - 部署指南

**分支**: `qwenx-arch`  
**版本**: 0.8.0  
**最后更新**: 2026-03-25

---

## 🚀 快速安装（两行命令）

```bash
# 1. 下载安装脚本并执行
curl -fsSL https://raw.githubusercontent.com/your-org/oh-my-litecode/qwenx-arch/scripts/install-archlinux.sh | sudo bash

# 2. 切换到 qwen 用户并开始使用
su - qwen && qwenx "你好，请帮我写一个 Python 函数"
```

---

## 📋 完整安装流程

### 步骤 1: 运行安装脚本

```bash
# 方法 A: 一键安装（推荐）
curl -fsSL https://raw.githubusercontent.com/your-org/oh-my-litecode/qwenx-arch/scripts/install-archlinux.sh | sudo bash

# 方法 B: 手动下载后安装
wget https://raw.githubusercontent.com/your-org/oh-my-litecode/qwenx-arch/scripts/install-archlinux.sh
sudo bash install-archlinux.sh
```

### 步骤 2: 验证安装

```bash
# 切换到 qwen 用户
su - qwen

# 检查版本
oml --version
qwenx --version

# 运行健康检查
oml platform doctor
```

### 步骤 3: 配置 API 密钥（可选）

```bash
# 切换到 qwen 用户
su - qwen

# 配置 Qwen API 密钥
export QWEN_API_KEY="sk-your-api-key-here"
oml qwen ctx7 set "sk-your-key@mykey"

# 或者编辑配置文件
nano ~/.local/home/qwenx/.qwen/settings.json
```

### 步骤 4: 开始使用

```bash
# 基本对话
qwenx "你好"

# 代码帮助
qwenx "帮我写一个快速排序算法"

# 使用 Context7 查询文档
qwenx "查询 React Hooks 的使用方法"

# 查看帮助
qwenx --help
oml --help
```

---

## 📁 安装位置

| 组件 | 路径 |
|------|------|
| **OML 主目录** | `/home/qwen/develop/oh-my-litecode` |
| **qwenx 命令** | `/usr/local/bin/qwenx` |
| **oml 命令** | `/usr/local/bin/oml` |
| **配置文件** | `/home/qwen/.local/home/qwenx/.qwen/` |
| **会话数据** | `/home/qwen/.oml/sessions/` |

---

## 🔧 常用命令

### 基础命令

```bash
# 查看帮助
qwenx --help
oml --help

# 平台检测
oml platform detect
oml platform doctor

# 插件管理
oml plugins list
oml plugins info qwen
```

### Qwen 功能

```bash
# 对话
qwenx "你好，请帮我写一个 Python 函数"

# Context7 密钥管理
oml qwen ctx7 list
oml qwen ctx7 current
oml qwen ctx7 rotate

# 模型管理
oml qwen models list
oml qwen models sync
```

### Worker 池

```bash
# 初始化 Worker 池
oml pool init --min 2 --max 10

# 提交任务
oml worker spawn qwen --task "分析项目结构"

# 查看状态
oml worker status
```

---

## ⚠️ 故障排查

### 问题 1: `qwenx: command not found`

**解决方案**:
```bash
# 检查符号链接
ls -la /usr/local/bin/qwenx

# 如果不存在，重新创建
sudo ln -sf /home/qwen/develop/oh-my-litecode/oml /usr/local/bin/qwenx
```

### 问题 2: 权限错误

**解决方案**:
```bash
# 修复权限
sudo chown -R qwen:qwen /home/qwen/develop/oh-my-litecode
sudo chown -R qwen:qwen /home/qwen/.local
sudo chown -R qwen:qwen /home/qwen/.oml
```

### 问题 3: API 密钥错误

**解决方案**:
```bash
# 检查密钥配置
oml qwen ctx7 list
oml qwen ctx7 current

# 重新设置密钥
oml qwen ctx7 set "sk-new-key@alias"
```

---

## 📚 文档链接

- [快速开始](../../../blob/qwenx-arch/QUICKSTART.md)
- [完整使用指南](../../../blob/qwenx-arch/docs/USER-GUIDE.md)
- [架构概览](../../../blob/qwenx-arch/docs/oml/ARCHITECTURE-OVERVIEW.md)
- [部署指南](../../../blob/qwenx-arch/docs/oml/DEPLOYMENT-GUIDE.md)

---

## 🔗 相关资源

- **GitHub**: https://github.com/your-org/oh-my-litecode
- **问题反馈**: https://github.com/your-org/oh-my-litecode/issues
- **讨论区**: https://github.com/your-org/oh-my-litecode/discussions

---

**维护者**: OML Team  
**许可**: MIT License
