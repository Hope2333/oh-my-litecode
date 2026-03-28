# Grep-App MCP - Local Code Search

TypeScript implementation of Grep-App MCP service for OML.

## Features

- ✅ Natural language code search
- ✅ Regular expression search
- ✅ Count pattern matches
- ✅ List files with matches
- ✅ Advanced search with context
- ✅ Configurable exclude directories

## Installation

```bash
cd packages/plugins/mcps/grep-app
npm install
```

## Usage

### Initialize Agent

```typescript
import { GrepAppAgent } from '@oml/plugin-grep-app';

const agent = new GrepAppAgent();
await agent.initialize({
  defaultPath: '/path/to/code',
  maxResults: 100,
  excludeDirs: ['node_modules', '.git'],
});
```

### Natural Language Search

```typescript
const result = await agent.searchIntent({
  query: 'find all Python functions',
  extensions: ['py'],
});
```

### Regex Search

```typescript
const result = await agent.searchRegex({
  pattern: 'def \\w+\\(',
  extensions: ['py'],
});
```

### Count Matches

```typescript
const result = await agent.countMatches({
  pattern: 'TODO|FIXME',
  extensions: ['ts', 'js'],
});
```

### List Files with Matches

```typescript
const result = await agent.filesWithMatches({
  pattern: 'import.*from',
  extensions: ['ts'],
});
```

### Call Tool

```typescript
const result = await agent.callTool({
  name: 'grep_regex',
  arguments: {
    pattern: 'console\\.log',
    extensions: ['js', 'ts'],
  },
});
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

### GrepAppAgent

#### Methods

- `initialize(config)`: Initialize the agent
- `shutdown()`: Shutdown the agent
- `searchIntent(options)`: Natural language search
- `searchRegex(options)`: Regex pattern search
- `countMatches(options)`: Count matches
- `filesWithMatches(options)`: List files with matches
- `advancedSearch(options)`: Advanced search
- `callTool(toolCall)`: Call a tool
- `listTools()`: List available tools

## Tools

| Tool | Description |
|------|-------------|
| grep_search_intent | Natural language code search |
| grep_regex | Regular expression search |
| grep_count | Count pattern matches |
| grep_files_with_matches | List files with matches |
| grep_advanced | Advanced search with options |

## Configuration

| Option | Default | Description |
|--------|---------|-------------|
| defaultPath | `.` | Default search path |
| maxResults | `100` | Maximum results to return |
| excludeDirs | `['node_modules', '.git', ...]` | Directories to exclude |
| mode | `stdio` | Operation mode |

## License

MIT
