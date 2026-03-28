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
cd packages/plugins/mcps/context7
npm install
```

## Usage

### Enable Local Mode

```typescript
import { Context7Agent } from '@oml/plugin-context7';

const agent = new Context7Agent();
await agent.initialize({ mode: 'local' });
await agent.enable('local');
```

### Enable Remote Mode

```typescript
await agent.initialize({ mode: 'remote', apiKey: 'sk-your-api-key' });
await agent.enable('remote', 'sk-your-api-key');
```

### Get Library Documentation

```typescript
const result = await agent.getLibraryDocs('react', 'hooks');
console.log(result.data);
```

### Search Documentation

```typescript
const result = await agent.searchDocs('TypeScript generics', 'typescript');
console.log(result.data);
```

### Check Status

```typescript
const status = await agent.getStatus();
console.log(`Context7 MCP: ${status.enabled ? 'enabled' : 'disabled'}`);
```

### Disable

```typescript
await agent.disable();
```

## Development

```bash
# Build
npm run build

# Run tests
npm test

# Watch mode
npm run dev
```

## API

### Context7Agent

#### Methods

- `initialize(config)`: Initialize the agent with configuration
- `shutdown()`: Shutdown the agent
- `enable(mode, apiKey)`: Enable Context7 MCP
- `disable()`: Disable Context7 MCP
- `getStatus()`: Get Context7 status
- `getLibraryDocs(libraryName, query)`: Get library documentation
- `searchDocs(query, library)`: Search documentation
- `callTool(toolCall)`: Call a Context7 tool
- `listTools()`: List available tools

## License

MIT
