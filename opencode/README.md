# OpenCode 定制和扩展

本目录包含针对 OpenCode 的专门定制、扩展和功能移植。

## 目录结构

```
opencode/
├── extensions/          # OpenCode 扩展
├── plugins/             # MCP 服务器和插件
├── commands/            # 自定义命令
├── scripts/             # 辅助脚本
└── docs/                # 文档
```

## OpenCode 快速开始

### 安装 OpenCode
```bash
# 使用 bun
bunx @opencode/cli

# 或使用 npx
npx @opencode/cli
```

### 配置
```bash
# 创建配置文件
mkdir -p ~/.opencode
cat > ~/.opencode/config.json << CONF
{
  "model": "qwen-coder",
  "provider": "qwen"
}
CONF
```

## 扩展开发

### OpenCode MCP 服务器
```json
{
  "mcpServers": {
    "my-server": {
      "command": "node",
      "args": ["server.js"]
    }
  }
}
```

## 参考文档

- [OpenCode GitHub](https://github.com/opencode-ai/opencode)
- [MCP 协议](https://modelcontextprotocol.io/)
