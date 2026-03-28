# WebSearch MCP - TypeScript Implementation

WebSearch MCP service for OML using Exa AI - TypeScript implementation.

## Features

- ✅ Web search using Exa AI
- ✅ Code context retrieval from GitHub/StackOverflow
- ✅ Advanced search with deep analysis
- ✅ URL crawling
- ✅ Local caching with TTL
- ✅ Citation tracking

## Installation

```bash
cd packages/plugins/mcps/websearch
npm install
```

## Usage

### Initialize Agent

```typescript
import { WebSearchAgent } from '@oml/plugin-websearch';

const agent = new WebSearchAgent();
await agent.initialize({
  apiKey: 'your-exa-api-key',
  baseUrl: 'https://api.exa.ai',
  timeout: 30,
});
```

### Web Search

```typescript
const result = await agent.search({
  query: 'React hooks tutorial',
  numResults: 10,
  useAutoprompt: true,
  type: 'auto',
});
```

### Get Code Context

```typescript
const result = await agent.getCodeContext({
  query: 'Python async await example',
  tokensNum: 5000,
});
```

### Call Tool

```typescript
const result = await agent.callTool({
  name: 'web_search_exa',
  arguments: {
    query: 'TypeScript generics',
    numResults: 5,
  },
});
```

### Cache Management

```typescript
// Clear cache
agent.clearCache();

// Get cache stats
const stats = agent.getCacheStats();
console.log(`Cache size: ${stats.size}, Valid entries: ${stats.entries}`);

// List sources
const sources = agent.listSources();
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

### WebSearchAgent

#### Methods

- `initialize(config)`: Initialize the agent
- `shutdown()`: Shutdown the agent
- `search(options)`: Search the web
- `getCodeContext(options)`: Get code context
- `clearCache()`: Clear cache
- `getCacheStats()`: Get cache statistics
- `listSources()`: List cached sources
- `callTool(toolCall)`: Call a tool
- `listTools()`: List available tools

## Tools

| Tool | Description |
|------|-------------|
| web_search_exa | Search the web using Exa AI |
| get_code_context_exa | Get code context from GitHub/StackOverflow |
| web_search_advanced_exa | Advanced web search with deep analysis |
| crawling_exa | Crawl a specific URL |

## Configuration

| Option | Default | Description |
|--------|---------|-------------|
| baseUrl | `https://api.exa.ai` | Exa API base URL |
| apiKey | `''` | Exa API key |
| timeout | `30` | Request timeout in seconds |
| cacheEnabled | `true` | Enable caching |
| cacheTtl | `3600` | Cache TTL in seconds |
| cacheMaxSize | `1000` | Maximum cache entries |

## Environment Variables

| Variable | Description |
|----------|-------------|
| EXA_API_KEY | Exa API key |
| EXA_BASE_URL | Exa API base URL |
| EXA_TIMEOUT | Request timeout |

## License

MIT
