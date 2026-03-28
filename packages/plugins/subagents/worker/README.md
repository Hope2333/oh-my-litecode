# Worker Subagent

Implements Commander-Worker architecture pattern for spawning and managing subagent tasks.

## Features

- **Task Spawning**: Spawn new subagent tasks with isolated environments
- **Task Management**: Track and manage running tasks
- **Scope Isolation**: Prevent conflicts between concurrent tasks
- **Background Execution**: Run tasks in background mode
- **Log Streaming**: View task logs in real-time
- **Conflict Detection**: Detect and prevent scope conflicts

## Commands

- `spawn` - Spawn a new subagent task
- `status` - Show task status
- `logs` - Show task logs
- `cancel` - Cancel running task
- `wait` - Wait for all tasks
- `info` - Show task details

## Usage

```typescript
import { WorkerAgent } from '@oml/plugin-worker';

const agent = new WorkerAgent();
await agent.initialize({ maxConcurrentTasks: 5 });

// Spawn a new task
const result = await agent.spawn('qwen', {
  task: 'Implement user authentication',
  scope: 'src/auth/**',
  background: true,
});

// Check task status
const status = await agent.status();
const runningStatus = await agent.status('running');

// View task logs
const logs = await agent.logs({ taskId: result.taskId, follow: true });

// Cancel a task
await agent.cancel(result.taskId);

// Wait for all tasks
await agent.wait();

// Get task info
const info = await agent.info(result.taskId);
```

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| maxConcurrentTasks | number | 5 | Maximum concurrent tasks |
| taskTimeout | number | 3600 | Task timeout in seconds |
| logRetention | number | 7 | Log retention days |

## Task Status

- `pending` - Task waiting to start
- `running` - Task currently executing
- `completed` - Task finished successfully
- `failed` - Task failed with error
- `cancelled` - Task was cancelled

## Scope Patterns

- `**` - All files (default)
- `src/**` - All files in src/
- `**/*.ts` - All TypeScript files
- `src/auth/**` - All files in src/auth/

## License

MIT
