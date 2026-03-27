# Grep-App MCP - Local Code Search

**Note**: This is a **local code search** MCP service inspired by [grep.app](https://grep.app), but runs entirely on your local machine.

## Features

- ✅ Search local code with natural language
- ✅ Regular expression search
- ✅ Search across GitHub repositories (via grep.app API)
- ✅ Count matches
- ✅ List matching files
- ✅ MCP stdio protocol

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

### MCP Stdio Mode

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

## Configuration

### Local Search (Default)

Searches your local codebase using GNU grep.

### Remote Search (Optional)

To search GitHub repositories via grep.app API:

```bash
python -m grep_app_mcp --enable --remote-api-key "your-github-token"
```

## API

### Tools

#### grep_search_intent

Natural language code search.

**Parameters:**
- `query` (required): Search query
- `path` (optional): Local search path (default: ".")
- `extensions` (optional): File extensions

#### grep_regex

Regular expression search.

**Parameters:**
- `pattern` (required): Regex pattern
- `path` (optional): Search path
- `extensions` (optional): File extensions

#### grep_count

Count pattern matches.

#### grep_files_with_matches

List files with matches.

## Difference from grep.app

| Feature | grep.app | This MCP |
|---------|----------|----------|
| Search Target | GitHub repositories | Local codebase |
| Backend | Vercel servers | GNU grep (local) |
| API | Private | Open source (MIT) |
| Cost | Free | Free |

## License

MIT
