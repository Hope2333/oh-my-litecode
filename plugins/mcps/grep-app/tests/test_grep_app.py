"""Tests for Grep-App MCP"""

import asyncio
import json
import pytest
from pathlib import Path
from tempfile import TemporaryDirectory

# Import the module to test
import sys
sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from grep_app_mcp import GrepAppMCP, SearchOptions, enable_grep_app, disable_grep_app


class TestSearchOptions:
    """Test SearchOptions model"""
    
    def test_default_values(self):
        options = SearchOptions(query="test")
        assert options.path == "."
        assert options.extensions is None
        assert options.max_results == 100
        assert len(options.exclude_dirs) > 0
    
    def test_custom_values(self):
        options = SearchOptions(
            query="test",
            path="/src",
            extensions=["py", "js"],
            max_results=50,
        )
        assert options.path == "/src"
        assert options.extensions == ["py", "js"]
        assert options.max_results == 50


class TestGrepAppMCP:
    """Test GrepAppMCP server"""
    
    @pytest.fixture
    def mcp(self):
        return GrepAppMCP()
    
    @pytest.fixture
    def test_dir(self):
        """Create test directory with sample files"""
        with TemporaryDirectory() as tmpdir:
            # Create test files in a subdirectory to avoid grep on the temp dir itself
            src_dir = Path(tmpdir) / "src"
            src_dir.mkdir()
            (src_dir / "test.py").write_text("def hello():\n    pass\n")
            (src_dir / "test.js").write_text("function hello() {}\n")
            yield src_dir
    
    @pytest.mark.asyncio
    async def test_list_tools(self, mcp):
        """Test list_tools handler"""
        # The handler is registered with the server
        # We can't directly test it without mocking the server
        assert mcp.server is not None
    
    @pytest.mark.asyncio
    async def test_grep_search_intent(self, mcp, test_dir):
        """Test natural language search"""
        result = await mcp._grep_search_intent({
            "query": "find all python functions",
            "path": str(test_dir),
        })
        
        assert "content" in result
        assert len(result["content"]) > 0
    
    @pytest.mark.asyncio
    async def test_grep_regex(self, mcp, test_dir):
        """Test regex search"""
        result = await mcp._grep_regex({
            "pattern": "def \\w+",
            "path": str(test_dir),
            "extensions": ["py"],
        })
        
        assert "content" in result
        content = json.loads(result["content"][0]["text"])
        assert len(content) > 0
    
    @pytest.mark.asyncio
    async def test_grep_count(self, mcp, test_dir):
        """Test count matches"""
        result = await mcp._grep_count({
            "pattern": "hello",
            "path": test_dir,
        })
        
        assert "content" in result
    
    @pytest.mark.asyncio
    async def test_grep_files_with_matches(self, mcp, test_dir):
        """Test list files with matches"""
        result = await mcp._grep_files_with_matches({
            "pattern": "hello",
            "path": test_dir,
        })
        
        assert "content" in result
        content = json.loads(result["content"][0]["text"])
        assert isinstance(content, list)


class TestEnableDisable:
    """Test enable/disable functions"""
    
    @pytest.fixture
    def temp_settings(self):
        """Create temporary settings file"""
        with TemporaryDirectory() as tmpdir:
            settings_file = Path(tmpdir) / "settings.json"
            settings_file.write_text('{}')
            yield settings_file
    
    def test_enable_grep_app(self, temp_settings):
        """Test enable grep-app"""
        enable_grep_app(str(temp_settings))
        
        settings = json.loads(temp_settings.read_text())
        assert "mcpServers" in settings
        assert "grep-app" in settings["mcpServers"]
    
    def test_disable_grep_app(self, temp_settings):
        """Test disable grep-app"""
        # First enable
        enable_grep_app(str(temp_settings))
        
        # Then disable
        disable_grep_app(str(temp_settings))
        
        settings = json.loads(temp_settings.read_text())
        assert "grep-app" not in settings.get("mcpServers", {})
