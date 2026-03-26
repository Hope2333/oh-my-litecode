# Aider 定制和扩展

本目录包含针对 Aider (aider-chat) 的专门定制、扩展和功能移植。

## 目录结构

```
aider/
├── extensions/          # Aider 扩展
├── plugins/             # 自定义插件
├── commands/            # 自定义命令
├── scripts/             # 辅助脚本
└── docs/                # 文档
```

## Aider 快速开始

### 安装 Aider
```bash
pip install aider-chat
```

### 配置
```bash
# 创建配置文件
mkdir -p ~/.aider
cat > ~/.aider.conf.yml << CONF
model: qwen/qwen-coder-plus
confirm-edit: false
auto-commits: true
CONF
```

### 使用
```bash
# 基本使用
aider

# 指定文件
aider file.py

# 使用配置
aider --config ~/.aider.conf.yml
```

## 扩展开发

### Aider 命令扩展
Aider 支持通过 `.aider.commands` 目录添加自定义命令：

```
~/.aider.commands/
└── mycommand.sh
```

### 环境变量
```bash
export AIDER_MODEL=qwen/qwen-coder-plus
export AIDER_API_KEY=your-key
export AIDER_API_BASE=https://api.example.com/v1
```

## 参考文档

- [Aider 官方文档](https://aider.chat/)
- [Aider GitHub](https://github.com/paul-gauthier/aider)
- [配置指南](https://aider.chat/docs/config.html)
