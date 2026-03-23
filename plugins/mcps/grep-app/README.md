# Grep-App MCP - Python Implementation

Grep-App MCP service for OML (Oh-My-Litecode) - Python implementation.

## Features

- ✅ Natural language code search
- ✅ Regular expression search
- ✅ Count matches
- ✅ List matching files
- ✅ MCP stdio protocol
- ✅ Type-safe with Pydantic

## Installation

```bash
cd plugins/mcps/grep-app
pip install -e .
```

## Usage

### Enable in Qwen Code

```bash
python -m grep_app_mcp --enable
```

### MCP Stdio Mode (for Qwen Code)

```bash
python -m grep_app_mcp --mode stdio
```

### Check Status

```bash
python -m grep_app_mcp --mode status
```

### Disable

```bash
python -m grep_app_mcp --mode disable
```

## Development

```bash
# Install dev dependencies
pip install -e ".[dev]"

# Run tests
pytest

# Run with coverage
pytest --cov=grep_app_mcp
```

## Configuration

Grep-App MCP stores configuration in `~/.qwen/settings.json`:

```json
{
  "mcpServers": {
    "grep-app": {
      "command": "python",
      "args": ["-m", "grep_app_mcp", "--mode", "stdio"],
      "protocol": "mcp",
      "enabled": true
    }
  }
}
```

## API

### Tools

#### grep_search_intent

Natural language code search.

**Parameters:**
- `query` (required): Search query (e.g., "find all Python functions")
- `path` (optional): Search path (default: ".")
- `extensions` (optional): File extensions (e.g., ["py", "js"])

**Example:**
```python
result = await mcp.call_tool('grep_search_intent', {
    'query': 'find all async functions',
    'extensions': ['py'],
})
```

#### grep_regex

Regular expression search.

**Parameters:**
- `pattern` (required): Regex pattern
- `path` (optional): Search path
- `extensions` (optional): File extensions

**Example:**
```python
result = await mcp.call_tool('grep_regex', {
    'pattern': 'def \\w+\\(',
    'extensions': ['py'],
})
```

#### grep_count

Count pattern matches.

**Parameters:**
- `pattern` (required): Pattern to count
- `path` (optional): Search path

#### grep_files_with_matches

List files with matches.

**Parameters:**
- `pattern` (required): Pattern to search
- `path` (optional): Search path

## Migration from Bash

This Python implementation replaces the Bash version (`main.sh`).

### Key Changes

| Feature | Bash | Python |
|---------|------|--------|
| MCP protocol | Manual stdio | Official MCP SDK |
| Data validation | Manual parsing | Pydantic models |
| Error handling | Exit codes | Exceptions |
| Testing | Manual | pytest + asyncio |

### Migration Guide

1. **Backup existing config:**
   ```bash
   cp ~/.qwen/settings.json ~/.qwen/settings.json.bak
   ```

2. **Install Python version:**
   ```bash
   cd plugins/mcps/grep-app
   pip install -e .
   ```

3. **Enable new version:**
   ```bash
   python -m grep_app_mcp --enable
   ```

4. **Test:**
   ```bash
   python -m grep_app_mcp --mode status
   ```

## System Requirements

- Python 3.10+
- GNU grep
- GNU find

## License

MIT
