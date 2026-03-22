# OML 快速参考卡片

## 安装与设置

```bash
# 添加 PATH
export PATH="$HOME/develop/oh-my-litecode:$PATH"

# 验证安装
oml --help
oml platform doctor
```

## 常用命令

### 平台相关
```bash
oml platform detect          # 检测平台 (termux/gnu-linux)
oml platform info            # 显示平台信息
oml platform doctor          # 健康检查
```

### 插件管理
```bash
oml plugins list             # 列出所有插件
oml plugins list agents      # 列出 agent 插件
oml plugins enable qwen      # 启用 qwen 插件
oml plugins info qwen        # 查看 qwen 插件信息
```

### Qwen (原 qwenx)
```bash
# 对话
oml qwen "你好"
oml qwen "写一个 Python 函数"

# Context7 密钥
oml qwen ctx7 list                    # 列出密钥
oml qwen ctx7 current                 # 当前密钥
oml qwen ctx7 set "key@alias"         # 设置密钥
oml qwen ctx7 rotate                  # 切换密钥
oml qwen ctx7 mode local|remote       # 切换模式

# 模型
oml qwen models list                  # 列出模型
```

### 构建
```bash
# opencode
oml build --project opencode --target termux-dpkg --ver 1.2.10
oml build --project opencode --target gnu-arch --ver 1.2.10

# bun
oml build --project bun --target termux-pacman --ver 1.3.9
```

### OpenCode 集成
```bash
oml opencode diagnose
oml opencode plugin list
oml opencode skill hook post_upgrade
```

## 环境变量

```bash
# Qwen API
export QWEN_API_KEY="sk-..."
export QWEN_BASE_URL="https://..."

# Context7
export CONTEXT7_API_KEY="ctx7sk-..."
```

## qwenx 兼容性

在 ~/.bashrc 中添加：
```bash
qwenx() { oml qwen "$@"; }
```

## 插件开发

```bash
# 创建模板
oml plugins create my-agent agent

# 目录结构
plugins/agents/my-agent/
├── plugin.json
├── main.sh
└── scripts/
    ├── post-install.sh
    └── pre-uninstall.sh
```

## 测试

```bash
# 运行测试套件
./tests/run-tests.sh

# 手动测试
oml platform detect
oml plugins list
oml qwen --help
```

## 目录结构

```
oh-my-litecode/
├── oml              # 主入口
├── core/            # 核心模块
│   ├── platform.sh
│   └── plugin-loader.sh
├── plugins/         # 插件仓库
│   └── agents/qwen/
├── solve-android/   # 子项目
├── tests/           # 测试
└── docs/            # 文档
```

## 故障排除

```bash
# 检查依赖
oml platform doctor

# 查看配置目录
oml platform info | grep "Config Dir"

# 检查插件
oml plugins list
oml plugins info qwen
```

## 相关链接

- 完整文档：README-OML.md
- 插件架构：OML-PLUGINS.md
- 测试套件：tests/run-tests.sh
