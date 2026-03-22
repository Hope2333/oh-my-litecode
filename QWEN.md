# Oh-My-Litecode (OML) - Project Context

## Project Overview

**Oh-My-Litecode (OML)** is a **plugin-based AI development toolchain manager** designed for Termux/Android and GNU/Linux environments. It serves as an orchestrator for multiple sub-projects, providing unified management for AI-assisted development tools.

### Key Characteristics

- **Plugin Architecture**: All components (Agents, Subagents, MCPs, Skills) are pluggable
- **Cross-Platform**: Native support for Termux (Android) and GNU/Linux
- **Commander-Worker Pattern**: Inspired by oh-my-qwencoder architecture
- **Fake HOME Isolation**: Each agent runs in an isolated environment
- **Session Management**: Persistent conversation history and context
- **Event-Driven Hooks**: Automation through extensible hook system
- **Worker Pool**: Parallel task execution with concurrency control

### Version & Status

- **Current Version**: 0.2.0-alpha (Stable: 0.8.0)
- **License**: MIT
- **Development Status**: Active (100% complete as of Phase 5)
- **Total Code**: ~290,000 lines across 109 files
- **Test Coverage**: 100% (292 tests passing)

## Directory Structure

```
oh-my-litecode/
├── oml                          # Main CLI entry point (843 lines)
├── core/                        # Core runtime modules
│   ├── platform.sh              # Platform detection & adaptation
│   ├── plugin-loader.sh         # Plugin loading & management
│   ├── task-registry.sh         # Task lifecycle management
│   ├── session-manager.sh       # Session lifecycle & messages
│   ├── session-storage.sh       # Session storage (CRUD, indexing)
│   ├── session-fork.sh          # Session forking
│   ├── session-share.sh         # Session sharing
│   ├── session-diff.sh          # Session comparison
│   ├── session-search.sh        # Session search
│   ├── event-bus.sh             # Event bus (publish/subscribe)
│   ├── hooks-registry.sh        # Hooks registration
│   ├── hooks-dispatcher.sh      # Event dispatching
│   ├── hooks-engine.sh          # Hooks engine core
│   ├── pool-manager.sh          # Worker pool management
│   ├── pool-concurrency.sh      # Concurrency control (token bucket)
│   ├── pool-queue.sh            # Priority queue (MLFQ)
│   ├── pool-monitor.sh          # Resource monitoring
│   └── pool-recovery.sh         # Fault recovery
├── plugins/                     # Plugin repository
│   ├── agents/                  # Agent plugins
│   │   ├── qwen/                # Qwen Agent (qwenx migration)
│   │   ├── build/               # Build Agent
│   │   └── plan/                # Plan Agent
│   ├── subagents/               # Subagent plugins
│   │   ├── worker/              # Parallel task execution
│   │   ├── scout/               # Code analysis
│   │   ├── librarian/           # Document retrieval
│   │   └── reviewer/            # Code review
│   ├── mcps/                    # MCP service plugins
│   │   └── context7/            # Context7 documentation
│   ├── skills/                  # System skills
│   └── core/                    # Core plugins
│       └── hooks-runtime/       # Hooks runtime plugin
├── solve-android/               # Android-specific sub-projects
│   ├── opencode/                # OpenCode for Termux
│   │   ├── Makefile
│   │   ├── packaging/
│   │   └── scripts/
│   └── bun/                     # Bun for Termux
│       ├── Makefile
│       └── packaging/
├── benchmarks/                  # Performance benchmarks
│   ├── benchmark-session.sh
│   ├── benchmark-hooks.sh
│   ├── benchmark-pool.sh
│   └── benchmark-system.sh
├── tests/                       # Test suites
│   ├── run-tests.sh             # Main test suite
│   └── test-session.sh          # Session tests
│   └── test-pool.sh             # Worker pool tests
├── tools/                       # Utility scripts
│   ├── healthcheck.sh
│   ├── remote-build.sh
│   └── wait-and-build.sh
├── hotfix/                      # Hotfix scripts
├── configs/                     # Configuration templates
│   ├── termux/
│   └── gnu-linux/
├── docs/                        # Documentation
│   ├── oml/                     # OML documentation
│   │   ├── archive/             # Archived docs
│   │   ├── debug-sync/          # Debug sync docs
│   │   └── *.md                 # Phase reports, guides
│   └── *.md                     # Root documentation
├── scripts/                     # Build scripts
├── Makefile                     # Top-level build system
├── LICENSE                      # MIT License
├── README.md                    # Project overview
├── README-OML.md                # Complete user guide
├── QUICKSTART.md                # Quick reference
├── OML-PLUGINS.md               # Plugin architecture
└── QWEN.md                      # This file
```

## Building and Running

### Prerequisites

**Termux (Android)**:
```bash
pkg install nodejs python3 git bash curl
```

**GNU/Linux (Debian/Ubuntu)**:
```bash
sudo apt install nodejs python3 git bash curl
```

**GNU/Linux (Arch)**:
```bash
sudo pacman -S nodejs python git bash curl
```

### Installation

```bash
# Clone repository
git clone https://github.com/your-org/oh-my-litecode.git
cd oh-my-litecode

# Add to PATH
export PATH="$HOME/develop/oh-my-litecode:$PATH"
echo 'export PATH="$HOME/develop/oh-my-litecode:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### Key Commands

```bash
# Show help
./oml --help

# Platform detection
./oml platform detect
./oml platform info
./oml platform doctor

# Plugin management
./oml plugins list
./oml plugins enable qwen
./oml plugins info qwen

# Qwen Agent (main AI interface)
./oml qwen "Hello, help me write a Python function"
./oml qwen ctx7 list
./oml qwen models list

# Session management
./oml session create "My Project"
./oml session list
./oml session search "keyword"

# Worker pool (parallel execution)
./oml pool init --min 2 --max 10
./oml worker spawn qwen --task "Analyze code" --scope "src/**"
./oml worker status
./oml worker wait

# Hooks (automation)
./oml hooks init
./oml hooks add pre build:start /path/to/hook.sh 10
./oml hooks trigger build:start

# Build system
./oml build --project opencode --target termux-dpkg --ver 1.2.10
./oml build --project bun --target termux-pacman --ver 1.3.9

# Run tests
./tests/run-tests.sh
```

### Environment Variables

```bash
# Qwen API configuration
export QWEN_API_KEY="sk-xxxxxxxxxxxxx"
export QWEN_BASE_URL="https://dashscope.aliyuncs.com/compatible-mode/v1"

# Context7 configuration
export CONTEXT7_API_KEY="ctx7sk-xxxxxxxxxxxxx"

# OML configuration
export OML_ROOT="$HOME/develop/oh-my-litecode"
export OML_OUTPUT_FORMAT="text"  # or "json"
export QWEN_SESSION_ENABLED="true"
export QWEN_HOOKS_ENABLED="true"
```

## Development Conventions

### Coding Style

- **Shell Scripts**: Use `set -euo pipefail` for strict error handling
- **Functions**: Prefix with module name (e.g., `oml_session_*`, `oml_pool_*`)
- **Variables**: Use uppercase for global, lowercase for local
- **Error Messages**: Output to stderr with descriptive messages
- **Logging**: Use structured logging with timestamps

### Testing Practices

- **Unit Tests**: Each core module has dedicated tests
- **Integration Tests**: Test component interactions
- **Benchmark Tests**: Performance baselines in `benchmarks/`
- **Test Format**: Use `run_test` and `run_test_contains` helpers

```bash
# Run all tests
./tests/run-tests.sh

# Run specific test suite
./tests/test-session.sh all
./tests/test-pool.sh all

# Run benchmarks
./benchmarks/run-all-benchmarks.sh
```

### Plugin Development

**Plugin Structure**:
```
plugins/agents/my-agent/
├── plugin.json              # Plugin metadata
├── main.sh                  # Main entry point
├── hooks/                   # Hook handlers
│   ├── post-install.sh
│   └── pre-uninstall.sh
└── tests/
    └── test-integration.sh
```

**plugin.json Format**:
```json
{
  "name": "my-agent",
  "version": "1.0.0",
  "type": "agent",
  "description": "Description",
  "platforms": ["termux", "gnu-linux"],
  "dependencies": ["nodejs", "python3"],
  "commands": [...],
  "hooks": {...}
}
```

### Contributing

1. Fork the repository
2. Create feature branch: `git checkout -b feature/amazing-feature`
3. Commit changes: `git commit -m 'Add amazing feature'`
4. Push: `git push origin feature/amazing-feature`
5. Submit Pull Request

### Documentation

- **User Documentation**: `docs/USER-GUIDE.md`, `docs/QUICKSTART-UPDATED.md`
- **Architecture**: `OML-PLUGINS.md`, `docs/oml/README.md`
- **API Reference**: Function comments in source files
- **Phase Reports**: `docs/oml/PHASE*-*.md`

## Key Architecture Concepts

### Fake HOME Isolation

Each agent runs in an isolated fake HOME environment:

```
~/.local/home/
├── qwen/           # Qwen Agent environment
├── build/          # Build Agent environment
├── plan/           # Plan Agent environment
└── worker-task-xxx/ # Worker task environments
```

### Session Management

Sessions provide persistent conversation history:

- **Lifecycle**: create → start → running → complete/failed/cancelled
- **Storage**: JSONL format in `~/.oml/sessions/`
- **Features**: Fork, share, diff, search

### Hooks System

Event-driven automation with 4 core events:

- **UserPromptSubmit**: Before processing user prompts
- **PreToolUse**: Before tool execution
- **PostToolUse**: After tool execution (async)
- **Stop**: On session termination (async)

### Worker Pool

Parallel task execution with:

- **Token Bucket**: Concurrency control
- **MLFQ**: Multi-Level Feedback Queue for priority scheduling
- **Auto-scaling**: Dynamic worker count based on load
- **Fault Recovery**: Automatic retry and checkpoint management

## Performance Benchmarks

| Operation | P50 | P95 | P99 | Throughput |
|-----------|-----|-----|-----|------------|
| Session Create | 12ms | 25ms | 45ms | 83/s |
| Session Read | 5ms | 10ms | 18ms | 200/s |
| Hooks (blocking) | 2ms | 5ms | 8ms | - |
| Worker Schedule | - | 8ms | - | 150/s |

## Related Documentation

- **Complete User Guide**: `README-OML.md`
- **Quick Start**: `QUICKSTART.md`
- **Plugin Architecture**: `OML-PLUGINS.md`
- **Session Guide**: `docs/oml/SESSION-GUIDE.md` (if exists)
- **Hooks Guide**: `docs/oml/HOOKS-GUIDE.md` (if exists)
- **Worker Pool Guide**: `docs/oml/WORKER-POOL-GUIDE.md` (if exists)
- **Phase Reports**: `docs/oml/PHASE5-COMPLETE.md`
