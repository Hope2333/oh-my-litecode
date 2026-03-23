"""Tests for Grep-App MCP - Local Code Search"""

import asyncio
import json
import pytest
from pathlib import Path
from tempfile import TemporaryDirectory

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
        assert len(options.exclude_dirs) > 5
    
    def test_custom_values(self):
        options = SearchOptions(
            query="test",
            path="/src",
            extensions=["py", "js"],
            max_results=50,
            case_sensitive=True,
        )
        assert options.path == "/src"
        assert options.extensions == ["py", "js"]
        assert options.max_results == 50
        assert options.case_sensitive is True


class TestGrepAppMCP:
    """Test GrepAppMCP server"""
    
    @pytest.fixture
    def mcp(self):
        return GrepAppMCP()
    
    @pytest.fixture
    def test_dir(self):
        """Create test directory with sample files"""
        with TemporaryDirectory() as tmpdir:
            src_dir = Path(tmpdir) / "src"
            src_dir.mkdir()
            (src_dir / "test.py").write_text("def hello():\n    pass\n\nasync def world():\n    pass\n")
            (src_dir / "test.js").write_text("function hello() {}\n\nasync function world() {}\n")
            yield src_dir
    
    @pytest.mark.asyncio
    async def test_list_tools(self, mcp):
        """Test list_tools handler exists"""
        assert mcp.server is not None
    
    @pytest.mark.asyncio
    async def test_grep_search_intent_python(self, mcp, test_dir):
        """Test natural language search for Python"""
        result = await mcp._grep_search_intent({
            "query": "find all python async functions",
            "path": str(test_dir),
        })
        
        assert "content" in result
        content = json.loads(result["content"][0]["text"])
        assert isinstance(content, list)
    
    @pytest.mark.asyncio
    async def test_grep_search_intent_javascript(self, mcp, test_dir):
        """Test natural language search for JavaScript"""
        result = await mcp._grep_search_intent({
            "query": "find all javascript async functions",
            "path": str(test_dir),
            "extensions": ["js"],
        })
        
        assert "content" in result
    
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
            "path": str(test_dir),
        })
        
        assert "content" in result
        # Count output contains numbers
        assert any(c.isdigit() for c in result["content"][0]["text"])
    
    @pytest.mark.asyncio
    async def test_grep_files_with_matches(self, mcp, test_dir):
        """Test list files with matches"""
        result = await mcp._grep_files_with_matches({
            "pattern": "hello",
            "path": str(test_dir),
        })
        
        assert "content" in result
        content = json.loads(result["content"][0]["text"])
        assert isinstance(content, list)
        assert len(content) > 0


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
        assert settings["mcpServers"]["grep-app"]["command"] == "python"
    
    def test_disable_grep_app(self, temp_settings):
        """Test disable grep-app"""
        # First enable
        enable_grep_app(str(temp_settings))
        
        # Then disable
        disable_grep_app(str(temp_settings))
        
        settings = json.loads(temp_settings.read_text())
        assert "grep-app" not in settings.get("mcpServers", {})
    
    def test_status_not_configured(self, temp_settings, capsys):
        """Test status when not configured"""
        from grep_app_mcp import print_status
        print_status(str(temp_settings))
        captured = capsys.readouterr()
        assert "not configured" in captured.out
