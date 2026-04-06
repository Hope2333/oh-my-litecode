# OML Core — Shared Logic Layer Specification

## Purpose

OML Core provides platform-independent logic shared across all CLI adapters. No adapter should reimplement these capabilities.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    OML Core                              │
│                                                          │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────────┐  │
│  │ Worker Pool │  │ MLFQ Scheduler│  │ Plugin System  │  │
│  │ • Spawn     │  │ • Priority Q  │  │ • Discover     │  │
│  │ • Monitor   │  │ • Feedback    │  │ • Load/Unload  │  │
│  │ • Scale     │  │ • Aging       │  │ • Resolve      │  │
│  └─────────────┘  └──────────────┘  └────────────────┘  │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────────┐  │
│  │ Hooks Engine│  │ Session Mgmt │  │ MCP Gateway    │  │
│  │ • Register  │  │ • Lifecycle  │  │ • Registry     │  │
│  │ • Trigger   │  │ • Compaction │  │ • Progressive  │  │
│  │ • Chain     │  │ • Fork       │  │ • Proxy        │  │
│  └─────────────┘  └──────────────┘  └────────────────┘  │
└─────────────────────────────────────────────────────────┘
         ▲                    ▲                    ▲
         │                    │                    │
┌────────┴──────┐  ┌─────────┴───────┐  ┌────────┴──────┐
│ OpenCode      │  │ Qwen Code       │  │ Claude Code   │
│ Adapter       │  │ Adapter         │  │ Adapter       │
└───────────────┘  └─────────────────┘  └───────────────┘
```

## Core Components

### 1. Worker Pool (`packages/core/pool`)

Manages background agent execution with auto-scaling.

```typescript
interface WorkerPool {
  spawn(task: Task): Promise<Worker>;
  monitor(): PoolStatus;
  scale(target: number): void;
  kill(workerId: string): Promise<void>;
}
```

**Key features:**
- Auto-scaling based on queue depth
- Health monitoring with automatic restart
- Resource limits (CPU, memory)

### 2. MLFQ Scheduler (`packages/core/scheduler`)

Multi-Level Feedback Queue for task prioritization.

```typescript
interface Scheduler {
  enqueue(task: Task, priority: number): void;
  dequeue(): Task | null;
  requeue(task: Task, newPriority: number): void;
}
```

**Key features:**
- 4 priority levels (realtime, high, normal, low)
- Automatic priority aging
- Fair scheduling within same priority

### 3. Hooks Engine (`packages/core/hooks`)

Event-driven hook system for tool/session lifecycle.

```typescript
interface HooksEngine {
  register(event: string, handler: HookHandler): void;
  trigger(event: string, context: HookContext): Promise<void>;
  unregister(event: string, handler: HookHandler): void;
}
```

**Supported events:**
- `session:start` — Session initialization
- `session:end` — Session cleanup
- `tool:before` — Pre-tool validation
- `tool:after` — Post-tool verification
- `context:compact` — Before context compression

### 4. Session Manager (`packages/core/session`)

Manages AI session lifecycle, context, and compaction.

```typescript
interface SessionManager {
  create(config: SessionConfig): Session;
  get(id: string): Session | null;
  compact(id: string): Promise<void>;
  fork(id: string, options: ForkOptions): Session;
  list(): Session[];
}
```

### 5. MCP Gateway (`packages/core/mcp`)

Progressive MCP tool loading and proxy.

```typescript
interface MCPGateway {
  register(server: MCPServer): void;
  loadOnDemand(toolName: string): Promise<ToolDef>;
  listAvailable(): ToolDef[];
  invoke(toolName: string, args: Record<string, unknown>): Promise<any>;
}
```

**Key features:**
- On-demand tool definition loading (saves 36%+ context window)
- Tool result caching
- Error recovery with retry

### 6. Plugin System (`packages/core/plugin`)

Discovers, loads, and manages OML plugins.

```typescript
interface PluginSystem {
  discover(root: string): Plugin[];
  load(name: string): Plugin;
  unload(name: string): void;
  list(): Plugin[];
}
```

**Plugin types:**
- `agent` — Specialized AI agents
- `subagent` — Delegated execution agents
- `mcp` — MCP server configurations
- `skill` — Skill definitions

## Adapter Interface

Each CLI adapter connects to OML Core:

```typescript
interface CLIAdapter {
  // Core connection
  connect(core: OMLCore): Promise<void>;
  disconnect(): Promise<void>;

  // Platform-specific registration
  registerMCP(config: MCPConfig): Promise<void>;
  registerContext(content: string): Promise<void>;
  registerCommands(commands: Command[]): Promise<void>;

  // Lifecycle hooks
  onSessionStart(): Promise<void>;
  onSessionEnd(): Promise<void>;
  onBeforeTool(tool: ToolCall): Promise<void>;
  onAfterTool(tool: ToolCall, result: ToolResult): Promise<void>;
}
```

## Package Structure (Future)

```
packages/
├── core/           # OML Core (shared logic)
│   ├── pool/       # Worker pool
│   ├── scheduler/  # MLFQ scheduler
│   ├── hooks/      # Hooks engine
│   ├── session/    # Session manager
│   ├── mcp/        # MCP gateway
│   └── plugin/     # Plugin system
├── adapters/       # CLI adapters
│   ├── opencode/   # OpenCode adapter
│   ├── qwen/       # Qwen Code adapter
│   ├── gemini/     # Gemini CLI adapter
│   ├── claude/     # Claude Code adapter
│   └── aider/      # Aider adapter
└── cli/            # CLI entry point
```

## Current Implementation Status

| Component | Implementation | Location |
|-----------|---------------|----------|
| Worker Pool | ✅ Bash implementation | `core/pool-manager.sh` |
| MLFQ Scheduler | ✅ Bash implementation | `core/scheduler.sh` |
| Hooks Engine | ✅ Bash implementation | `core/hooks-engine.sh` |
| Session Manager | ✅ TypeScript | `src/core/session-manager.ts` |
| MCP Gateway | ✅ TypeScript | `src/core/mcp-gateway.ts` |
| Plugin System | ✅ Bash + TypeScript | `core/plugin-loader.sh` + `src/core/plugin-loader.ts` |

## Migration Plan

1. **Phase 1**: Document current Bash implementations (done)
2. **Phase 2**: Migrate Bash to TypeScript packages (pending)
3. **Phase 3**: Create unified adapter interface (pending)
4. **Phase 4**: Implement Qwen Code adapter using TypeScript core (pending)
