"""
Grep-App MCP Service - Local Code Search

Inspired by grep.app (https://grep.app) but runs locally.
Provides MCP service for code search using GNU grep.

Usage:
    python -m grep_app_mcp --mode stdio
"""

import asyncio
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Optional, List

from mcp.server import Server
from mcp.server.stdio import stdio_server
from pydantic import BaseModel, Field


class SearchOptions(BaseModel):
    """Search options"""
    query: str
    path: str = "."
    extensions: Optional[List[str]] = None
    exclude_dirs: List[str] = Field(default_factory=lambda: [
        "node_modules", ".git", "__pycache__", ".venv", "venv", "dist", "build",
        ".next", "coverage", ".nyc_output", "target", "bin", "obj"
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
    """Grep-App MCP Server - Local code search inspired by grep.app"""
    
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
                        "description": "Natural language code search (local codebase)",
                        "inputSchema": {
                            "type": "object",
                            "properties": {
                                "query": {
                                    "type": "string",
                                    "description": "Search query (e.g., 'find all Python async functions')",
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
                        "description": "Regular expression search in local files",
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
                        "description": "Count pattern matches in local files",
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
                        "description": "List local files with matches",
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
                return {
                    "content": [{"type": "text", "text": f"Unknown tool: {name}"}],
                    "isError": True
                }
    
    async def _run_grep(self, pattern: str, path: str, options: SearchOptions) -> List[GrepResult]:
        """Run grep command and parse results"""
        cmd = [
            "grep",
            "-r",           # Recursive
            "-n",           # Line numbers
            "--exclude-dir=" + "|".join(options.exclude_dirs),
        ]
        
        if not options.case_sensitive:
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
                        file_path, line_num, content = parts
                        results.append(GrepResult(
                            file=file_path,
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
        """Natural language search - converts to grep pattern"""
        query = arguments.get("query", "")
        path = arguments.get("path", ".")
        extensions = arguments.get("extensions")
        
        # Heuristic: detect language from query
        if not extensions:
            query_lower = query.lower()
            if "python" in query_lower or "def " in query_lower:
                extensions = ["py"]
            elif "javascript" in query_lower or "typescript" in query_lower:
                extensions = ["js", "ts", "jsx", "tsx"]
            elif "rust" in query_lower:
                extensions = ["rs"]
            elif "go" in query_lower or "golang" in query_lower:
                extensions = ["go"]
        
        # Extract keywords from natural language query
        keywords = query.lower()
        for word in ["find", "all", "search", "for", "show", "me", "the"]:
            keywords = keywords.replace(word, " ")
        keywords = keywords.strip()
        
        # Use first meaningful keyword as pattern
        pattern = keywords.split()[0] if keywords else query
        
        options = SearchOptions(
            query=query,
            path=path,
            extensions=extensions,
            use_regex=False,
        )
        
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
        
        cmd = [
            "grep",
            "-r",
            "-c",
            "--exclude-dir=node_modules,.git,__pycache__,.venv,dist,build",
            pattern,
            path
        ]
        
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
        
        cmd = [
            "grep",
            "-r",
            "-l",
            "--exclude-dir=node_modules,.git,__pycache__,.venv,dist,build",
            pattern,
            path
        ]
        
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
            
            files = [f for f in stdout.decode().strip().split("\n") if f]
            
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
            await self.server.run(read_stream, write_stream)


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
        "description": "Local code search (inspired by grep.app)",
    }
    
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(settings, indent=2))
    print("✓ Grep-App MCP enabled (local code search)")


def disable_grep_app(settings_path: Optional[str] = None):
    """Disable grep-app MCP"""
    path = _get_settings_path(settings_path)
    
    if not path.exists():
        print("✗ Settings file not found")
        return
    
    settings = json.loads(path.read_text())
    
    if "mcpServers" in settings and "grep-app" in settings["mcpServers"]:
        del settings["mcpServers"]["grep-app"]
        path.write_text(json.dumps(settings, indent=2))
        print("✓ Grep-App MCP disabled")
    else:
        print("✗ Grep-App MCP not enabled")


def print_status(settings_path: Optional[str] = None):
    """Print grep-app MCP status"""
    path = _get_settings_path(settings_path)
    
    if not path.exists():
        print("✗ Settings file not found")
        return
    
    settings = json.loads(path.read_text())
    mcp_servers = settings.get("mcpServers", {})
    
    if "grep-app" in mcp_servers:
        config = mcp_servers["grep-app"]
        enabled = config.get("enabled", True)
        print(f"Grep-App MCP: {'✓ enabled' if enabled else '✗ disabled'}")
        print(f"  Command: {config.get('command')} {' '.join(config.get('args', []))}")
        print(f"  Description: {config.get('description', 'Local code search')}")
    else:
        print("✗ Grep-App MCP: not configured")


def main():
    """CLI entry point"""
    import argparse
    
    parser = argparse.ArgumentParser(
        description="Grep-App MCP - Local code search (inspired by grep.app)"
    )
    parser.add_argument(
        "--mode",
        choices=["stdio", "enable", "disable", "status"],
        default="stdio"
    )
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
        asyncio.run(mcp.run_stdio())


if __name__ == "__main__":
    main()
