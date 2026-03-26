# Qwen Session Manager Extension

Session management TUI and CLI tools for Qwen Code.

## Features

- **Interactive TUI**: Curses-based terminal UI for session management
- **CLI Commands**: List, delete, clear, and view session details
- **Multi-select**: Mark multiple sessions for batch deletion
- **Session Details**: View session info and recent messages

## Usage

### Session Commands

| Command | Description |
|---------|-------------|
| `/session tui` | Launch interactive TUI interface |
| `/session list` | List all sessions |
| `/session json` | List sessions in JSON format |
| `/session delete <id>` | Delete a session by ID |
| `/session clear` | Clear all sessions |
| `/session info <id>` | Show session details |
| `/session help` | Show help |

### TUI Controls

| Key | Action |
|-----|--------|
| `↑/k` | Move up |
| `↓/j` | Move down |
| `Enter` | View session details |
| `d` | Delete selected session |
| `m` | Toggle multi-select mode |
| `x` | Mark/unmark session |
| `D` | Delete marked sessions |
| `r` | Refresh list |
| `C` | Clear all sessions |
| `?` | Toggle help |
| `q` | Quit |

## Installation

```bash
# Install from local path
qwen extensions link /path/to/qwen-session-manager

# Or install from GitHub (when published)
qwen extensions install https://github.com/Hope2333/oh-my-litecode/extensions/qwen-session-manager
```

## Extension Structure

```
qwen-session-manager/
├── qwen-extension.json    # Extension configuration
├── QWEN.md                # This file (context)
├── commands/
│   └── session.toml       # Session command definition
└── scripts/
    └── session_manager.py # Python TUI implementation
```
