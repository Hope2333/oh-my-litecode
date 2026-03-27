# MCP 集成示例

## 配置 MCP 服务器

### 1. 在 settings.json 中添加 MCP 配置

```json
{
  "mcpServers": {
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp@latest"],
      "trust": false
    },
    "filesystem": {
      "command": "node",
      "args": ["/path/to/filesystem-mcp-server.js"],
      "cwd": "/path/to/project"
    }
  }
}
```

### 2. 使用 OML CLI 管理 MCP

```bash
# 查看 MCP 状态
oml cloud status

# 同步 MCP 配置
oml cloud sync --direction push
```

## MCP 服务器示例

### 简单的文件系统 MCP 服务器

```javascript
#!/usr/bin/env node
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';

const server = new McpServer({
  name: 'filesystem-mcp',
  version: '1.0.0',
});

server.tool('read_file', async ({ path }) => {
  const content = await fs.promises.readFile(path, 'utf-8');
  return { content: [{ type: 'text', text: content }] };
});

server.tool('write_file', async ({ path, content }) => {
  await fs.promises.writeFile(path, content);
  return { content: [{ type: 'text', text: 'File written successfully' }] };
});

const transport = new StdioServerTransport();
await server.connect(transport);
```

## 验证 MCP 连接

```bash
# 测试 MCP 服务器
npx @modelcontextprotocol/inspector node filesystem-mcp-server.js
```
