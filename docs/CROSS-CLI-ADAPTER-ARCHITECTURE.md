# OML Cross-CLI Adapter Architecture

## Vision

OML (oh-my-litecode) serves as the **universal Body layer** for all major AI coding CLI tools. Each CLI gets a lightweight adapter that connects to OML's shared logic layer.

```
┌──────────────────────────────────────────────────────────────────┐
│                     AI-LTC (Brain)                               │
│  State Machine | Memory | Error Recovery | Security | Quality    │
│  (AI-LTC repo — NEVER mixed with OML)                            │
└───────────────────────────┬──────────────────────────────────────┘
                            │ Task/Result Protocol (JSON)
┌───────────────────────────┼──────────────────────────────────────┐
│                    OML (Body / oh-my-litecode)                    │
│                                                                   │
│  ┌──────────────────┐  ┌──────────────────┐  ┌────────────────┐  │
│  │  Shared Logic     │  │  Platform        │  │  Cross-CLI     │  │
│  │  (OML Core)       │  │  Adapters        │  │  Dispatcher    │  │
│  │                   │  │                  │  │                │  │
│  │ • Worker Pool     │  │ • OpenCode (OMO) │  │ • Task Routing │  │
│  │ • MLFQ Scheduler  │  │ • Qwen Code      │  │ • Reverse Call │  │
│  │ • Hooks Engine    │  │ • Gemini CLI     │  │ • State Sync   │  │
│  │ • Session Mgmt    │  │ • Claude Code    │  │ • Failover     │  │
│  │ • MCP Gateway     │  │ • Aider          │  │ • Result Aggr  │  │
│  │ • Plugin System   │  │ • Codex CLI      │  │                │  │
│  └──────────────────┘  └──────────────────┘  └────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
                            │
┌──────────┬───────────────┼───────────────┬──────────────────────┐
│ OpenCode │   Qwen Code   │  Claude Code  │  Aider / Codex / ... │
│ (OMO)    │  (qwencode)   │   (CC)        │                      │
└──────────┴───────────────┴───────────────┴──────────────────────┘
```

## Anti-Mixing Rule (CRITICAL)

**AI-LTC and OML are SEPARATE repositories. NEVER mix them.**

| Repository | Purpose | Location |
|------------|---------|----------|
| **AI-LTC** | Brain — state machine, memory, error recovery, security | `~/develop/AI-LTC` |
| **OML** | Body — plugin runtime, MCP gateway, session management, CLI adapters | `~/develop/oh-my-litecode` |

Communication between them is via:
1. **File-based protocol** — `.ai/state.json` (AI-LTC) ↔ OML session store
2. **MCP tools** — OML exposes LSP/AST/Session tools that AI-LTC agents can call
3. **Hook triggers** — AI-LTC state transitions → OML hook events

## Adapter Interface (Unified)

Every CLI adapter implements:

```typescript
interface CLIAdapter {
  // Platform detection
  detect(): boolean;

  // Registration
  registerMCP(config: MCPConfig): Promise<void>;
  registerContext(content: string): Promise<void>;
  registerCommands(commands: Command[]): Promise<void>;

  // Lifecycle
  onSessionStart(): Promise<void>;
  onSessionEnd(): Promise<void>;
  onBeforeTool(tool: ToolCall): Promise<void>;
  onAfterTool(tool: ToolCall, result: ToolResult): Promise<void>;

  // Cross-CLI dispatch
  dispatchTask(task: Task): Promise<TaskResult>;
  receiveTask(task: Task): Promise<TaskResult>;
}
```

## Current Adapter Status

| CLI | Adapter Dir | Extension Format | Status |
|-----|------------|-----------------|--------|
| OpenCode | `opencode/` | oh-my-openagent.json + Plugin SDK | ✅ Full (OMO) |
| Qwen Code | `qwen/` | qwen-extension.json + QWEN.md | 🔄 Partial |
| Gemini CLI | `gemini/` | gemini-extension.json + GEMINI.md | 🔄 Partial |
| Claude Code | `claude/` | claude-plugin.json + Skills | 📋 Entry |
| Aider | `aider/` | .aider.conf.yaml + Commands | 📋 Entry |
| Codex CLI | `codex/` | TBD | 📋 Entry |
| ForgeCode | `forgecode/` | TBD | 📋 Entry |

## Communication Protocol

### Task Dispatch (AI-LTC → OML → CLI)

```json
{
  "taskId": "task-<timestamp>-<random>",
  "source": "ai-ltc",
  "targetCLI": "qwen-code",
  "type": "subagent|skill|mcp",
  "capability": "explore",
  "payload": { "description": "...", "scope": "src/**" },
  "metadata": { "sessionId": "ses_abc", "phase": "EXECUTION" }
}
```

### Result Return (CLI → OML → AI-LTC)

```json
{
  "taskId": "task-<timestamp>-<random>",
  "status": "success|error|timeout",
  "result": { "findings": ["file1.ts", "file2.ts"] },
  "duration": 12.5,
  "workerId": "worker-xyz"
}
```

## File Structure

```
oh-my-litecode/
├── qwen/                    # Qwen Code adapter
│   ├── extensions/
│   │   └── qwen-session-manager/
│   │       ├── qwen-extension.json
│   │       ├── QWEN.md
│   │       ├── commands/
│   │       └── scripts/
│   └── README.md
├── gemini/                  # Gemini CLI adapter
│   ├── extensions/
│   └── README.md
├── opencode/                # OpenCode adapter (OMO)
│   ├── commands/
│   ├── docs/
│   ├── extensions/
│   ├── plugins/
│   ├── scripts/
│   └── README.md
├── claude/                  # Claude Code adapter
│   ├── commands/
│   ├── docs/
│   ├── extensions/
│   ├── plugins/
│   ├── scripts/
│   └── README.md
├── aider/                   # Aider adapter
├── codex/                   # Codex CLI adapter
├── forgecode/               # ForgeCode adapter
├── src/                     # Shared logic (ARCHIVED → migrate to packages/)
├── packages/                # Shared packages (future)
├── plugins/                 # OML plugin system
├── AI-CLI-EXTENSIONS.md     # This document
├── OML-PLUGINS.md           # Plugin documentation
└── README.md                # Main documentation
```
