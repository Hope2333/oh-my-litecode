# Librarian Subagent

Documentation search, Context7 queries, web search, and knowledge compilation.

## Features

- **Context7 Integration**: Query library documentation via Context7 MCP
- **Web Search**: Search the web using Exa MCP
- **Knowledge Compilation**: Compile knowledge from multiple sources
- **Cache Management**: Efficient caching with TTL support
- **Multiple Output Formats**: JSON, Markdown, Text

## Commands

- `search` - Search documentation (Context7 + web)
- `query` - Query Context7 MCP for library documentation
- `websearch` - Web search using Exa MCP
- `compile` - Compile knowledge from multiple sources
- `sources` - List and manage citation sources
- `cache` - Manage search cache

## Usage

```typescript
import { LibrarianAgent } from '@oml/plugin-librarian';

const agent = new LibrarianAgent();
await agent.initialize({ maxResults: 10, outputFormat: 'markdown' });

// Search documentation
const result = await agent.search('react hooks', { package: 'react' });

// Query Context7
const queryResult = await agent.query('react', 'how to use useEffect');

// Web search
const webResult = await agent.websearch('rust async best practices');

// Compile knowledge
const compiled = await agent.compile('React Hooks Guide', { 
  package: 'react',
  web: true 
});
```

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| maxResults | number | 10 | Maximum search results |
| outputFormat | string | 'markdown' | Output format (json/markdown/text) |
| context7Enabled | boolean | true | Enable Context7 integration |
| webSearchEnabled | boolean | true | Enable web search integration |
| cacheEnabled | boolean | true | Enable result caching |
| cacheTTL | number | 3600 | Cache TTL in seconds |

## License

MIT
