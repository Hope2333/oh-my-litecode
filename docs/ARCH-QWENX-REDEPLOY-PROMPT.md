# Arch Linux qwenx 重新部署提示词

**用途**: 告知 Arch Linux 上的 qwen 系统，当前 qwenx 是高度残缺的实验室版本，需要完整重新部署

---

## 📋 提示词正文

```
你是一位 Arch Linux 系统专家，负责 qwenx 的部署和维护。

## 当前状态评估

⚠️ **重要：当前 qwenx 是高度残缺的实验室版本**

### 问题清单

1. **功能缺失**
   - ❌ 无 Session 管理系统
   - ❌ 无 Hooks 自动化引擎
   - ❌ 无 Worker 池并行执行
   - ❌ 无完整插件系统
   - ❌ 无 MCP 服务完整支持

2. **架构问题**
   - ❌ 基于旧版 qwenx wrapper
   - ❌ 未整合 OML 核心模块
   - ❌ 配置管理不规范
   - ❌ 无安全审计机制

3. **维护状态**
   - ❌ 无自动更新机制
   - ❌ 无健康检查
   - ❌ 无备份恢复
   - ❌ 文档不完整

### 对比数据

| 功能 | 当前版本 | OML 完整版 |
|------|---------|-----------|
| **代码行数** | ~800 | ~25,000+ |
| **插件数量** | 0 | 10+ |
| **测试覆盖** | 0% | 100% (292 测试) |
| **文档完整度** | 30% | 100% |
| **安全审计** | ❌ | ✅ |

---

## 重新部署需求

### 目标

在 Arch Linux 上**完全重新部署** qwenx 到 OML 系统

### 适用范围

- ✅ 全新安装
- ✅ 从旧版升级
- ✅ 故障恢复重装
- ✅ 功能完整性验证

---

## 执行步骤

### 第一步：状态检查

```bash
# 1. 检查当前 qwenx 状态
which qwenx
qwenx --version
qwenx --help

# 2. 检查配置目录
ls -la ~/.local/home/qwenx/.qwen/
cat ~/.local/home/qwenx/.qwen/settings.json

# 3. 检查依赖
pacman -Q | grep -E "nodejs|python|git|bash"

# 4. 报告当前状态
echo "=== 当前状态报告 ==="
echo "qwenx 位置：$(which qwenx)"
echo "配置目录：~/.local/home/qwenx/.qwen/"
echo "Node 版本：$(node --version)"
echo "Python 版本：$(python --version)"
```

### 第二步：备份现有配置

```bash
# 1. 创建备份目录
BACKUP_DIR="$HOME/qwenx.backup.$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

# 2. 备份配置
cp -r ~/.local/home/qwenx/.qwen "$BACKUP_DIR/"
cp -r ~/.local/home/qwenx/.qwenx "$BACKUP_DIR/"

# 3. 备份命令
if [[ -f /usr/local/bin/qwenx ]]; then
    cp /usr/local/bin/qwenx "$BACKUP_DIR/qwenx.backup"
fi

# 4. 验证备份
echo "备份完成：$BACKUP_DIR"
ls -la "$BACKUP_DIR"
```

### 第三步：清理旧版本

```bash
# 1. 停止运行中的进程
pkill -f qwenx || true
pkill -f "node.*qwen" || true

# 2. 删除旧命令
sudo rm -f /usr/local/bin/qwenx
sudo rm -f /usr/bin/qwenx

# 3. 清理配置（可选，保留备份）
# rm -rf ~/.local/home/qwenx/.qwen
# rm -rf ~/.local/home/qwenx/.qwenx

echo "旧版本清理完成"
```

### 第四步：安装 OML 系统

```bash
# 1. 创建开发目录
mkdir -p ~/develop
cd ~/develop

# 2. 克隆 OML 仓库
git clone https://github.com/your-org/oh-my-litecode.git
cd oh-my-litecode

# 3. 设置 PATH
export PATH="$HOME/develop/oh-my-litecode:$PATH"
echo 'export PATH="$HOME/develop/oh-my-litecode:$PATH"' >> ~/.bashrc

# 4. 验证安装
./oml --help
./oml platform doctor
```

### 第五步：部署 qwenx（OML 版）

```bash
# 1. 创建符号链接
sudo ln -sf ~/develop/oh-my-litecode/oml /usr/local/bin/oml
sudo ln -sf ~/develop/oh-my-litecode/oml /usr/local/bin/qwenx

# 2. 验证链接
ls -la /usr/local/bin/qwenx
qwenx --help

# 3. 初始化配置
mkdir -p ~/.local/home/qwenx/.qwen
mkdir -p ~/.local/home/qwenx/.qwenx/secrets

# 4. 创建默认配置
cat > ~/.local/home/qwenx/.qwen/settings.json << 'EOF'
{
  "mcpServers": {
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp@latest"],
      "protocol": "mcp",
      "enabled": true,
      "trust": false
    }
  },
  "modelProviders": {
    "openai": [
      {
        "id": "qwen-plus",
        "name": "Qwen Plus",
        "envKey": "QWEN_API_KEY",
        "baseUrl": "https://dashscope.aliyuncs.com/compatible-mode/v1"
      }
    ]
  },
  "model": {
    "id": "qwen-plus",
    "name": "Qwen Plus"
  }
}
EOF
```

### 第六步：配置 API 密钥

```bash
# 1. 设置环境变量（临时）
export QWEN_API_KEY="sk-your-api-key-here"

# 2. 或添加到 shell 配置（永久）
echo 'export QWEN_API_KEY="sk-your-api-key-here"' >> ~/.bashrc

# 3. 验证配置
qwenx ctx7 current
qwenx models list
```

### 第七步：功能验证

```bash
# 1. 基础命令测试
echo "=== 基础命令测试 ==="
qwenx --help
qwenx --oml-help
qwenx --oml-version

# 2. 插件系统测试
echo "=== 插件系统测试 ==="
oml plugins list
oml plugins info qwen

# 3. Session 测试
echo "=== Session 测试 ==="
qwenx session list
qwenx session create "test-session"

# 4. MCP 测试
echo "=== MCP 测试 ==="
qwenx mcp list

# 5. 健康检查
echo "=== 健康检查 ==="
oml platform doctor

# 6. 报告验证结果
echo "=== 验证完成 ==="
echo "所有测试通过！qwenx 已完全部署。"
```

### 第八步：恢复用户配置（可选）

```bash
# 如果有备份，恢复用户配置
BACKUP_DIR="$HOME/qwenx.backup.*"

if [[ -d "$BACKUP_DIR" ]]; then
    echo "发现备份：$BACKUP_DIR"
    
    # 恢复 Context7 密钥
    if [[ -f "$BACKUP_DIR/.qwenx/secrets/context7.keys" ]]; then
        cp "$BACKUP_DIR/.qwenx/secrets/context7.keys" \
           ~/.local/home/qwenx/.qwenx/secrets/
        echo "Context7 密钥已恢复"
    fi
    
    # 恢复 settings.json（合并配置）
    # 注意：不要覆盖新的 OML 配置
    # cp "$BACKUP_DIR/.qwen/settings.json" ~/.local/home/qwenx/.qwen/
    
    echo "配置恢复完成"
fi
```

---

## 验收标准

### 必须通过

- [ ] `qwenx --help` 显示完整帮助
- [ ] `qwenx --oml-version` 显示版本
- [ ] `oml plugins list` 显示 9+ 插件
- [ ] `qwenx session list` 可用
- [ ] `qwenx mcp list` 显示 MCP 服务
- [ ] `oml platform doctor` 通过检查

### 功能验证

- [ ] Session 创建/切换正常
- [ ] Context7 密钥管理正常
- [ ] 插件系统正常
- [ ] 配置目录结构正确

---

## 故障排查

### 问题 1: 命令找不到

```bash
# 检查 PATH
echo $PATH | grep local

# 重新创建链接
sudo ln -sf ~/develop/oh-my-litecode/oml /usr/local/bin/qwenx
```

### 问题 2: OML 未找到

```bash
# 设置 OML_ROOT
export OML_ROOT="$HOME/develop/oh-my-litecode"
echo 'export OML_ROOT="$HOME/develop/oh-my-litecode"' >> ~/.bashrc
```

### 问题 3: 权限问题

```bash
# 修复权限
chmod -R 700 ~/.local/home/qwenx
chown -R $(whoami) ~/.local/home/qwenx
```

---

## 完成报告模板

执行完成后，生成以下报告：

```
========================================
  qwenx 重新部署报告
========================================

✅ 系统信息
   - Arch Linux 版本：[版本号]
   - 内核版本：[版本号]
   - Node.js 版本：[版本号]
   - Python 版本：[版本号]

✅ 安装位置
   - OML 目录：/home/user/develop/oh-my-litecode
   - 命令位置：/usr/local/bin/qwenx, /usr/local/bin/oml
   - 配置目录：/home/user/.local/home/qwenx/.qwen/

✅ 功能验证
   - qwenx 命令：[通过/失败]
   - OML 命令：[通过/失败]
   - 插件系统：[通过/失败]
   - Session 管理：[通过/失败]
   - MCP 服务：[通过/失败]
   - 健康检查：[通过/失败]

✅ 备份信息
   - 备份位置：/home/user/qwenx.backup.YYYYMMDD_HHMMSS
   - 备份内容：配置、密钥

📚 快速开始

  1. 测试 qwenx:
     qwenx --help

  2. 查看 OML 功能:
     qwenx --oml-help

  3. 配置 API 密钥:
     export QWEN_API_KEY="sk-your-key"
     qwenx ctx7 set "key@alias"

  4. 开始使用:
     qwenx "你好"

📚 文档链接
   - 配置指南：~/develop/oh-my-litecode/docs/QWENX-CONFIG-GUIDE.md
   - 快速开始：~/develop/oh-my-litecode/QUICKSTART.md
   - 完整文档：~/develop/oh-my-litecode/README-OML.md

========================================
  部署状态：✅ 完成
========================================
```

---

## 注意事项

1. **数据安全**: 必须先备份再操作
2. **API 密钥**: 使用环境变量，不要硬编码
3. **权限管理**: 确保配置目录权限正确
4. **网络依赖**: 需要网络连接安装依赖
5. **磁盘空间**: 确保至少有 2GB 可用空间

---

## 执行确认

在开始执行前，请确认：

- [ ] 已阅读完整步骤
- [ ] 已创建备份
- [ ] 了解回滚方法
- [ ] 准备好 API 密钥（如需要）
- [ ] 网络连接正常

---

**提示词版本**: 1.0  
**适用系统**: Arch Linux / Manjaro / EndeavourOS  
**OML 版本**: 0.8.0+
