# Scout Subagent

Code analysis, dependency mapping, and repository statistics.

## Features

- **Codebase Analysis**: Structure and complexity analysis
- **File Tree Visualization**: Generate directory tree views
- **Dependency Mapping**: Analyze imports and dependencies
- **Complexity Analysis**: Code complexity metrics
- **Statistics Generation**: File type and size statistics
- **Comprehensive Reporting**: Full analysis reports

## Commands

- `analyze` - Analyze codebase structure and complexity
- `tree` - Generate file tree visualization
- `deps` - Analyze dependencies and imports
- `report` - Generate comprehensive analysis report
- `stats` - Show file type statistics

## Usage

```typescript
import { ScoutAgent } from '@oml/plugin-scout';

const agent = new ScoutAgent();
await agent.initialize({ maxDepth: 10, outputFormat: 'markdown' });

// Analyze codebase
const analysis = await agent.analyze('./src');

// Generate file tree
const tree = await agent.tree('./src', { maxDepth: 3 });

// Analyze dependencies
const deps = await agent.deps('./src');

// Generate dependency graph (DOT format)
const graph = await agent.deps('./src', { graph: true });

// Generate comprehensive report
const report = await agent.report('./src');

// Get statistics
const stats = await agent.stats('./src');
```

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| outputFormat | string | 'markdown' | Output format |
| maxDepth | number | 10 | Maximum tree depth |
| excludePatterns | string[] | [...] | Exclude patterns |

## Output Formats

- `json` - Machine-readable JSON output
- `markdown` - Human-readable Markdown report
- `text` - Plain text summary

## License

MIT
