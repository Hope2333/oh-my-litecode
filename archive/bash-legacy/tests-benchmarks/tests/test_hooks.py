"""Tests for Hooks Engine"""

import asyncio
import pytest
import sys
import os
from pathlib import Path

# Add src to path
src_path = Path(__file__).parent.parent / "src"
sys.path.insert(0, str(src_path))

from hooks.engine import HooksEngine
from hooks.types import Hook, HookType, EventPriority, HooksConfig, Event, ExecutionContext


class TestHookTypes:
    """Test hook type definitions"""
    
    def test_hook_creation(self):
        hook = Hook(
            name="test-hook",
            event="test-event",
            handler="/path/to/handler.sh",
        )
        assert hook.name == "test-hook"
        assert hook.event == "test-event"
        assert hook.enabled is True
        assert hook.priority == EventPriority.NORMAL
    
    def test_hook_to_dict(self):
        hook = Hook(name="test", event="evt", handler="h.sh")
        d = hook.to_dict()
        assert d["name"] == "test"
        assert d["enabled"] is True
    
    def test_event_creation(self):
        event = Event(name="test-event", data={"key": "value"})
        assert event.name == "test-event"
        assert event.data["key"] == "value"
        assert event.cancelled is False
    
    def test_event_cancel(self):
        event = Event(name="test")
        event.cancel()
        assert event.cancelled is True


class TestHooksEngine:
    """Test hooks engine"""
    
    @pytest.fixture
    def engine(self):
        """Create test engine"""
        eng = HooksEngine()
        eng.initialize()
        return eng
    
    def test_initialize(self, engine):
        assert engine.initialized is True
    
    def test_register_hook(self, engine):
        hook = Hook(name="test", event="evt", handler="h.sh")
        engine.register_hook(hook)
        
        hooks = engine.list_hooks("evt")
        assert len(hooks) == 1
        assert hooks[0].name == "test"
    
    def test_unregister_hook(self, engine):
        hook = Hook(name="test", event="evt", handler="h.sh")
        engine.register_hook(hook)
        
        result = engine.unregister_hook("evt", "test")
        assert result is True
        
        hooks = engine.list_hooks("evt")
        assert len(hooks) == 0
    
    def test_unregister_nonexistent_hook(self, engine):
        result = engine.unregister_hook("evt", "nonexistent")
        assert result is False
    
    def test_list_hooks(self, engine):
        hook1 = Hook(name="test1", event="evt1", handler="h1.sh")
        hook2 = Hook(name="test2", event="evt2", handler="h2.sh")
        engine.register_hook(hook1)
        engine.register_hook(hook2)
        
        all_hooks = engine.list_hooks()
        assert len(all_hooks) == 2
    
    def test_enable_disable_hook(self, engine):
        hook = Hook(name="test", event="evt", handler="h.sh")
        engine.register_hook(hook)
        
        # Disable
        result = engine.disable_hook("evt", "test")
        assert result is True
        assert hook.enabled is False
        
        # Enable
        result = engine.enable_hook("evt", "test")
        assert result is True
        assert hook.enabled is True
    
    def test_get_stats(self, engine):
        hook1 = Hook(name="test1", event="evt", handler="h1.sh")
        hook2 = Hook(name="test2", event="evt", handler="h2.sh", enabled=False)
        engine.register_hook(hook1)
        engine.register_hook(hook2)
        
        stats = engine.get_stats()
        assert stats["total_hooks"] == 2
        assert stats["enabled_hooks"] == 1
        assert stats["disabled_hooks"] == 1
    
    def test_trigger_event_no_hooks(self, engine):
        event = asyncio.run(engine.trigger_event("nonexistent"))
        assert event.name == "nonexistent"
        assert event.cancelled is False
    
    def test_hook_priority_sorting(self, engine):
        hook1 = Hook(name="low", event="evt", handler="h.sh", priority=150)
        hook2 = Hook(name="high", event="evt", handler="h.sh", priority=50)
        hook3 = Hook(name="normal", event="evt", handler="h.sh", priority=100)
        
        engine.register_hook(hook1)
        engine.register_hook(hook2)
        engine.register_hook(hook3)
        
        hooks = engine.list_hooks("evt")
        assert hooks[0].name == "high"
        assert hooks[1].name == "normal"
        assert hooks[2].name == "low"


class TestHooksConfig:
    """Test hooks configuration"""
    
    def test_default_config(self):
        config = HooksConfig()
        assert config.enabled is True
        assert config.log_level == "INFO"
        assert config.timeout == 300
    
    def test_custom_config(self):
        config = HooksConfig(
            enabled=False,
            log_level="DEBUG",
            timeout=600,
        )
        assert config.enabled is False
        assert config.log_level == "DEBUG"
        assert config.timeout == 600
    
    def test_config_to_dict(self):
        config = HooksConfig()
        d = config.to_dict()
        assert "enabled" in d
        assert "log_level" in d
        assert "timeout" in d
