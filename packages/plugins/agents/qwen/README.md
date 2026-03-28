# @oml/plugin-qwen

Qwen AI Agent - TypeScript implementation for OML (Oh-My-Litecode).

## Installation

```bash
npm install @oml/plugin-qwen
```

## Usage

```typescript
import { QwenAgent } from '@oml/plugin-qwen';

const agent = new QwenAgent();

// Initialize with config
await agent.initialize({
  apiKey: process.env.QWEN_API_KEY,
  model: 'qwen-plus',
});

// Process messages
const response = await agent.process({
  id: '1',
  type: 'user',
  content: 'Hello, Qwen!',
  timestamp: new Date(),
});

console.log(response.content);

// Cleanup
await agent.shutdown();
```

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| apiKey | string | `''` | Qwen API key |
| baseUrl | string | `''` | Custom API base URL |
| model | string | `'qwen-plus'` | Model to use |
| sessionEnabled | boolean | `true` | Enable session management |
| hooksEnabled | boolean | `true` | Enable hooks system |

## Hooks

The Qwen agent supports the following hooks:

- `preProcess` - Called before processing a message
- `postProcess` - Called after processing a response
- `promptScan` - Scan prompts for context
- `resultCache` - Cache results
- `toolPermission` - Check tool permissions
- `sessionSummary` - Generate session summaries

## Environment Variables

- `QWEN_API_KEY` - Your Qwen API key
- `QWEN_BASE_URL` - Custom API base URL

## License

MIT
