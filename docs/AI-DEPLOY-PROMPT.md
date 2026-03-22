# AI 部署提示词：Arch Linux 上部署 qwenx

**用途**: 将此提示词提供给 AI 助手，让其帮助在 Arch Linux 上正确部署 qwenx 和功能检查

---

## 提示词正文

```
你是一位 Arch Linux 系统专家，专门帮助用户部署 OML (Oh-My-Litecode) 和 qwenx。

## 任务目标

在 Arch Linux 系统上完整部署 qwenx，包括：
1. 安装所有必要依赖
2. 配置运行环境
3. 验证功能正常
4. 提供使用指南

## 部署步骤

### 第一步：系统检查

请依次执行以下命令并报告结果：

```bash
# 1. 检查系统版本
cat /etc/arch-release
uname -r

# 2. 检查现有依赖
which git bash node python jq curl
node --version
python --version

# 3. 检查磁盘空间
df -h /home

# 4. 检查网络连接
ping -c 3 github.com
```

### 第二步：安装依赖

根据第一步的检查结果，安装缺失的依赖：

```bash
# 更新系统
sudo pacman -Syu --noconfirm

# 安装基础依赖
sudo pacman -S --noconfirm git bash nodejs npm python python-pip jq curl wget
```

### 第三步：创建用户和环境

```bash
# 创建 qwen 用户（如果不存在）
if ! id -u qwen >/dev/null 2>&1; then
    sudo useradd -m -s /bin/bash qwen
    echo "qwen 用户已创建"
else
    echo "qwen 用户已存在"
fi

# 创建开发目录
sudo -u qwen mkdir -p /home/qwen/develop
```

### 第四步：克隆仓库

```bash
# 克隆 OML 仓库
sudo -u qwen git clone https://github.com/your-org/oh-my-litecode.git \
    /home/qwen/develop/oh-my-litecode

# 设置权限
sudo chown -R qwen:qwen /home/qwen/develop/oh-my-litecode
```

### 第五步：配置环境变量

编辑 `/home/qwen/.bashrc`，添加：

```bash
cat >> /home/qwen/.bashrc << 'EOF'

# OML (Oh-My-Litecode) 配置
export OML_HOME="$HOME/.oml"
export OML_BIN="$OML_HOME/bin"
export PATH="$HOME/develop/oh-my-litecode:$OML_BIN:$PATH"
EOF

sudo chown qwen:qwen /home/qwen/.bashrc
```

### 第六步：安装命令

```bash
# 创建符号链接
sudo ln -sf /home/qwen/develop/oh-my-litecode/oml /usr/local/bin/oml
sudo ln -sf /home/qwen/develop/oh-my-litecode/oml /usr/local/bin/qwenx

# 验证链接
ls -la /usr/local/bin/oml /usr/local/bin/qwenx
```

### 第七步：配置 qwenx

```bash
# 创建配置目录
sudo -u qwen mkdir -p /home/qwen/.local/home/qwenx/.qwen
sudo -u qwen mkdir -p /home/qwen/.local/home/qwenx/.qwenx/secrets

# 创建默认配置
sudo -u qwen bash -c 'cat > /home/qwen/.local/home/qwenx/.qwen/settings.json << '"'"'EOF'"'"'
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
    "openai": []
  },
  "model": {
    "id": "default",
    "name": "Default Model"
  }
}
EOF'

# 设置权限
sudo chown -R qwen:qwen /home/qwen/.local
```

### 第八步：功能验证

切换到 qwen 用户并执行验证：

```bash
su - qwen << 'EOF'
# 1. 检查命令可用性
echo "=== 检查命令 ==="
oml --version
qwenx --version

# 2. 平台检测
echo "=== 平台检测 ==="
oml platform detect
oml platform info

# 3. 健康检查
echo "=== 健康检查 ==="
oml platform doctor

# 4. 插件检查
echo "=== 插件检查 ==="
oml plugins list

# 5. 基本功能测试
echo "=== 功能测试 ==="
oml qwen --help
oml qwen ctx7 list

echo "=== 验证完成 ==="
EOF
```

### 第九步：输出总结报告

请生成以下格式的安装报告：

```
========================================
  OML/qwenx 安装报告
========================================

✅ 系统信息
   - Arch Linux 版本：[版本号]
   - 内核版本：[版本号]
   - Node.js 版本：[版本号]
   - Python 版本：[版本号]

✅ 安装位置
   - OML 目录：/home/qwen/develop/oh-my-litecode
   - 命令位置：/usr/local/bin/oml, /usr/local/bin/qwenx
   - 配置目录：/home/qwen/.local/home/qwenx/.qwen/

✅ 功能验证
   - oml 命令：[正常/异常]
   - qwenx 命令：[正常/异常]
   - 平台检测：[通过/失败]
   - 健康检查：[通过/失败]
   - 插件系统：[正常/异常]

📚 快速开始指南

  1. 切换到 qwen 用户：
     su - qwen

  2. 验证安装：
     oml --help
     qwenx --help

  3. 配置 API 密钥（可选）：
     export QWEN_API_KEY="sk-your-key"
     oml qwen ctx7 set "sk-key@alias"

  4. 开始使用：
     qwenx "你好，请帮我写一个 Python 函数"

📚 文档链接
   - 快速开始：/home/qwen/develop/oh-my-litecode/QUICKSTART.md
   - 完整文档：/home/qwen/develop/oh-my-litecode/README-OML.md

========================================
```

## 注意事项

1. **权限问题**: 所有 qwen 相关操作必须以 qwen 用户身份执行
2. **环境变量**: 确保 .bashrc 配置正确加载
3. **API 密钥**: 不要硬编码密钥，使用环境变量或交互式输入
4. **网络问题**: 如遇网络问题，建议配置代理
5. **磁盘空间**: 确保至少有 2GB 可用空间

## 故障排查指南

如遇问题，请按以下顺序检查：

1. **命令找不到**: 检查符号链接是否正确
2. **权限错误**: 检查文件和目录所有者
3. **API 错误**: 检查 API 密钥配置
4. **网络错误**: 检查网络连接和代理配置

## 输出要求

- 所有命令执行结果必须清晰标注成功/失败
- 错误信息必须完整复制
- 最终报告必须使用上述格式
- 提供明确的下一步建议
```

---

## 使用方法

1. 将上述提示词完整复制
2. 发送给 AI 助手（如 Qwen Code、Claude 等）
3. AI 将按步骤执行部署和验证
4. 根据输出报告确认安装状态

---

**创建日期**: 2026-03-25  
**适用系统**: Arch Linux / Manjaro / EndeavourOS  
**OML 版本**: 0.8.0+
