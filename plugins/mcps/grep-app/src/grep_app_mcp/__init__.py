"""
Grep-App MCP Service - Python Implementation

Provides MCP (Model Context Protocol) service for code search and analysis.

Usage:
    # MCP stdio mode (for Qwen Code integration)
    python -m grep_app_mcp --mode stdio
    
    # HTTP mode
    python -m grep_app_mcp --mode http --port 8765
    
    # Enable in Qwen Code
    python -m grep_app_mcp --enable
"""

import asyncio
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Optional

from mcp.server import Server
from mcp.server.stdio import stdio_server
from pydantic import BaseModel, Field


class SearchOptions(BaseModel):
    """Search options for grep-app"""
    query: str
    path: str = "."
    extensions: Optional[list[str]] = None
    exclude_dirs: list[str] = Field(default_factory=lambda: [
        "node_modules", ".git", "__pycache__", ".venv", "venv", "dist", "build"
    ])
    max_results: int = 100
    case_sensitive: bool = False
    use_regex: bool = False


class GrepResult(BaseModel):
    """Single grep result"""
    file: str
    line: int
    column: int
    content: str
    match: str


class GrepAppMCP:
    """Grep-App MCP Server"""
    
    def __init__(self):
        self.server = Server("grep-app")
        self._setup_handlers()
    
    def _setup_handlers(self):
        """Setup MCP request handlers"""
        
        @self.server.list_tools()
        async def list_tools():
            return {
                "tools": [
                    {
                        "name": "grep_search_intent",
                        "description": "Natural language code search",
                        "inputSchema": {
                            "type": "object",
                            "properties": {
                                "query": {
                                    "type": "string",
                                    "description": "Search query (e.g., 'find all Python functions')",
                                },
                                "path": {
                                    "type": "string",
                                    "description": "Search path (default: current directory)",
                                },
                                "extensions": {
                                    "type": "array",
                                    "items": {"type": "string"},
                                    "description": "File extensions to search (e.g., ['py', 'js'])",
                                },
                            },
                            "required": ["query"],
                        },
                    },
                    {
                        "name": "grep_regex",
                        "description": "Regular expression search",
                        "inputSchema": {
                            "type": "object",
                            "properties": {
                                "pattern": {
                                    "type": "string",
                                    "description": "Regex pattern",
                                },
                                "path": {
                                    "type": "string",
                                    "description": "Search path",
                                },
                                "extensions": {
                                    "type": "array",
                                    "items": {"type": "string"},
                                    "description": "File extensions",
                                },
                            },
                            "required": ["pattern"],
                        },
                    },
                    {
                        "name": "grep_count",
                        "description": "Count pattern matches",
                        "inputSchema": {
                            "type": "object",
                            "properties": {
                                "pattern": {
                                    "type": "string",
                                    "description": "Pattern to count",
                                },
                                "path": {
                                    "type": "string",
                                    "description": "Search path",
                                },
                            },
                            "required": ["pattern"],
                        },
                    },
                    {
                        "name": "grep_files_with_matches",
                        "description": "List files with matches",
                        "inputSchema": {
                            "type": "object",
                            "properties": {
                                "pattern": {
                                    "type": "string",
                                    "description": "Pattern to search",
                                },
                                "path": {
                                    "type": "string",
                                    "description": "Search path",
                                },
                            },
                            "required": ["pattern"],
                        },
                    },
                ]
            }
        
        @self.server.call_tool()
        async def call_tool(name: str, arguments: dict):
            if name == "grep_search_intent":
                return await self._grep_search_intent(arguments)
            elif name == "grep_regex":
                return await self._grep_regex(arguments)
            elif name == "grep_count":
                return await self._grep_count(arguments)
            elif name == "grep_files_with_matches":
                return await self._grep_files_with_matches(arguments)
            else:
                return {"content": [{"type": "text", "text": f"Unknown tool: {name}"}], "isError": True}
    
    async def _run_grep(self, pattern: str, path: str, options: SearchOptions) -> list[GrepResult]:
        """Run grep command and parse results"""
        cmd = ["grep", "-r", "-n", "--exclude-dir=" + "|".join(options.exclude_dirs)]

        if options.case_sensitive:
            cmd.append("-i")
        if options.use_regex:
            cmd.append("-E")

        if options.extensions:
            for ext in options.extensions:
                cmd.append(f"--include=*.{ext}")

        cmd.extend([pattern, path])
        
        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            stdout, stderr = await proc.communicate()
            
            if proc.returncode == 1:  # No matches
                return []
            elif proc.returncode != 0:
                raise RuntimeError(f"grep failed: {stderr.decode()}")
            
            results = []
            for line in stdout.decode().splitlines():
                if ":" in line:
                    parts = line.split(":", 2)
                    if len(parts) >= 3:
                        file, line_num, content = parts
                        results.append(GrepResult(
                            file=file,
                            line=int(line_num),
                            column=0,
                            content=content.strip(),
                            match=pattern,
                        ))
                        if len(results) >= options.max_results:
                            break
            
            return results
        except FileNotFoundError:
            raise RuntimeError("grep not found. Please install GNU grep.")
    
    async def _grep_search_intent(self, arguments: dict) -> dict:
        """Natural language search"""
        query = arguments.get("query", "")
        path = arguments.get("path", ".")
        extensions = arguments.get("extensions")
        
        # Simple heuristic: detect language from query
        if not extensions:
            if "python" in query.lower() or "def " in query:
                extensions = ["py"]
            elif "javascript" in query.lower() or "function" in query:
                extensions = ["js", "ts", "jsx", "tsx"]
        
        options = SearchOptions(
            query=query,
            path=path,
            extensions=extensions,
            use_regex=False,
        )
        
        # Convert natural language to grep pattern
        # For simplicity, just search for keywords
        keywords = query.replace("find", "").replace("all", "").strip()
        pattern = keywords.split()[0] if keywords else query
        
        results = await self._run_grep(pattern, path, options)
        
        return {
            "content": [{
                "type": "text",
                "text": json.dumps([r.model_dump() for r in results], indent=2),
            }]
        }
    
    async def _grep_regex(self, arguments: dict) -> dict:
        """Regex search"""
        pattern = arguments.get("pattern", "")
        path = arguments.get("path", ".")
        extensions = arguments.get("extensions")
        
        options = SearchOptions(
            query=pattern,
            path=path,
            extensions=extensions,
            use_regex=True,
        )
        
        results = await self._run_grep(pattern, path, options)
        
        return {
            "content": [{
                "type": "text",
                "text": json.dumps([r.model_dump() for r in results], indent=2),
            }]
        }
    
    async def _grep_count(self, arguments: dict) -> dict:
        """Count matches"""
        pattern = arguments.get("pattern", "")
        path = arguments.get("path", ".")
        
        cmd = ["grep", "-r", "-c", "--exclude-dir=node_modules,.git,__pycache__", pattern, path]
        
        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            stdout, stderr = await proc.communicate()
            
            if proc.returncode != 0:
                return {
                    "content": [{"type": "text", "text": f"Error: {stderr.decode()}"}],
                    "isError": True,
                }
            
            return {
                "content": [{"type": "text", "text": stdout.decode()}],
            }
        except FileNotFoundError:
            return {
                "content": [{"type": "text", "text": "grep not found"}],
                "isError": True,
            }
    
    async def _grep_files_with_matches(self, arguments: dict) -> dict:
        """List files with matches"""
        pattern = arguments.get("pattern", "")
        path = arguments.get("path", ".")
        
        cmd = ["grep", "-r", "-l", "--exclude-dir=node_modules,.git,__pycache__", pattern, path]
        
        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            stdout, stderr = await proc.communicate()
            
            if proc.returncode != 0:
                return {
                    "content": [{"type": "text", "text": f"Error: {stderr.decode()}"}],
                    "isError": True,
                }
            
            files = stdout.decode().strip().split("\n")
            
            return {
                "content": [{
                    "type": "text",
                    "text": json.dumps(files, indent=2),
                }],
            }
        except FileNotFoundError:
            return {
                "content": [{"type": "text", "text": "grep not found"}],
                "isError": True,
            }
    
    async def run_stdio(self):
        """Run MCP server with stdio transport"""
        async with stdio_server() as (read_stream, write_stream):
            await self.server.run(
                read_stream,
                write_stream,
            )
    
    async def run_http(self, port: int = 8765):
        """Run MCP server with HTTP transport (not implemented yet)"""
        print(f"HTTP mode not implemented. Use stdio mode instead.")
        await self.run_stdio()


def main():
    """CLI entry point"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Grep-App MCP Service")
    parser.add_argument("--mode", choices=["stdio", "http", "enable", "disable", "status"], default="stdio")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--settings", type=str, help="Path to settings.json")
    
    args = parser.parse_args()
    
    if args.mode == "enable":
        enable_grep_app(args.settings)
    elif args.mode == "disable":
        disable_grep_app(args.settings)
    elif args.mode == "status":
        print_status(args.settings)
    else:
        mcp = GrepAppMCP()
        if args.mode == "http":
            asyncio.run(mcp.run_http(args.port))
        else:
            asyncio.run(mcp.run_stdio())


def _get_settings_path(settings_path: Optional[str]) -> Path:
    """Get settings file path"""
    if settings_path:
        return Path(settings_path)
    return Path.home() / ".qwen" / "settings.json"


def enable_grep_app(settings_path: Optional[str] = None):
    """Enable grep-app MCP in Qwen Code settings"""
    path = _get_settings_path(settings_path)
    
    if path.exists():
        settings = json.loads(path.read_text())
    else:
        settings = {"$schema": "https://opencode.ai/config.json"}
    
    if "mcpServers" not in settings:
        settings["mcpServers"] = {}
    
    settings["mcpServers"]["grep-app"] = {
        "command": "python",
        "args": ["-m", "grep_app_mcp", "--mode", "stdio"],
        "protocol": "mcp",
        "enabled": True,
    }
    
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(settings, indent=2))
    print("Grep-App MCP enabled")


def disable_grep_app(settings_path: Optional[str] = None):
    """Disable grep-app MCP"""
    path = _get_settings_path(settings_path)
    
    if not path.exists():
        print("Settings file not found")
        return
    
    settings = json.loads(path.read_text())
    
    if "mcpServers" in settings and "grep-app" in settings["mcpServers"]:
        del settings["mcpServers"]["grep-app"]
        path.write_text(json.dumps(settings, indent=2))
        print("Grep-App MCP disabled")
    else:
        print("Grep-App MCP not enabled")


def print_status(settings_path: Optional[str] = None):
    """Print grep-app MCP status"""
    path = _get_settings_path(settings_path)
    
    if not path.exists():
        print("Settings file not found")
        return
    
    settings = json.loads(path.read_text())
    mcp_servers = settings.get("mcpServers", {})
    
    if "grep-app" in mcp_servers:
        config = mcp_servers["grep-app"]
        enabled = config.get("enabled", True)
        print(f"Grep-App MCP: {'enabled' if enabled else 'disabled'}")
        print(f"Command: {config.get('command')} {' '.join(config.get('args', []))}")
    else:
        print("Grep-App MCP: not configured")


if __name__ == "__main__":
    main()
