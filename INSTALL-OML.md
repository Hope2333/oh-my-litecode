# OML CLI 安装指南

## 快速安装

### 方法 1: 用户本地安装 (推荐)

```bash
# 1. 创建本地 bin 目录
mkdir -p ~/.local/bin

# 2. 创建 oml 脚本
cat > ~/.local/bin/oml << 'SCRIPT'
#!/usr/bin/env node
import('/home/miao/develop/oh-my-litecode/packages/cli/dist/bin/oml.js');
SCRIPT

# 3. 添加执行权限
chmod +x ~/.local/bin/oml

# 4. 添加到 PATH (如果还没有)
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# 5. 测试
oml --help
```

### 方法 2: 直接运行

```bash
cd /home/miao/develop/oh-my-litecode
node packages/cli/dist/bin/oml.js --help
```

### 方法 3: NPM 全局安装 (需要 root 权限)

```bash
cd packages/cli
sudo npm link
```

## 验证安装

```bash
# 查看帮助
oml --help

# 查看版本
oml --version

# 列出插件
oml plugin list

# 显示迁移状态
oml plugin migrated
```

## 可用命令

- `oml qwen` - Qwen 代理控制器
- `oml plugin` - 插件管理 (40 个 TypeScript 插件)
- `oml cloud` - 云同步
- `oml perf` - 性能监控
- `oml tui` - TUI 界面

## 故障排除

### 命令未找到

确保 `~/.local/bin` 在 PATH 中：

```bash
export PATH="$HOME/.local/bin:$PATH"
```

### 权限问题

确保脚本有执行权限：

```bash
chmod +x ~/.local/bin/oml
```

### 构建问题

重新构建 CLI：

```bash
cd packages/cli
npm run build
```
