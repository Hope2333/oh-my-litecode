# Context7 MCP - TypeScript Implementation

Context7 MCP service for OML (Oh-My-Litecode) - TypeScript implementation.

## Features

- ✅ Local mode (runs `npx @upstash/context7-mcp`)
- ✅ Remote mode (uses Context7 API)
- ✅ MCP stdio mode (for Qwen Code integration)
- ✅ Type-safe configuration management
- ✅ Official MCP SDK integration

## Installation

```bash
cd plugins/mcps/context7
npm install
```

## Usage

### Enable Local Mode

```bash
npm run dev -- --mode local
```

### Enable Remote Mode

```bash
npm run dev -- --mode remote --api-key "sk-your-api-key"
```

### MCP Stdio Mode (for Qwen Code)

```bash
npm run dev -- --mode stdio
```

### Check Status

```bash
npm run dev -- --mode status
```

### Disable

```bash
npm run dev -- --mode disable
```

## Development

```bash
# Build
npm run build

# Run tests
npm test

# Watch mode
npm run test:watch

# Lint
npm run lint
```

## Configuration

Context7 MCP stores configuration in `~/.qwen/settings.json`:

```json
{
  "mcpServers": {
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp@latest"],
      "protocol": "mcp",
      "enabled": true
    }
  }
}
```

## API

### Tools

#### get-library-docs

Get documentation for a specific library.

**Parameters:**
- `libraryName` (required): Name of the library (e.g., "react", "vue")
- `query` (optional): Specific query (e.g., "hooks", "components")

**Example:**
```typescript
const docs = await mcp.callTool('get-library-docs', {
  libraryName: 'react',
  query: 'hooks',
});
```

#### search-docs

Search Context7 documentation.

**Parameters:**
- `query` (required): Search query
- `library` (optional): Library filter

**Example:**
```typescript
const results = await mcp.callTool('search-docs', {
  query: 'TypeScript generics',
  library: 'typescript',
});
```

## Migration from Bash

This TypeScript implementation replaces the Bash version (`main.sh`).

### Key Changes

| Feature | Bash | TypeScript |
|---------|------|------------|
| Config management | Python script | Type-safe functions |
| MCP protocol | Manual stdio | Official SDK |
| Error handling | Exit codes | Promises + try/catch |
| Testing | Manual | Vitest + 100% coverage |

### Migration Guide

1. **Backup existing config:**
   ```bash
   cp ~/.qwen/settings.json ~/.qwen/settings.json.bak
   ```

2. **Install TypeScript version:**
   ```bash
   cd plugins/mcps/context7
   npm install
   npm run build
   ```

3. **Update plugin.json:**
   ```json
   {
     "main": "dist/index.js"
   }
   ```

4. **Test:**
   ```bash
   npm run dev -- --mode status
   ```

## License

MIT
