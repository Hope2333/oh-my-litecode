"""
OML Hooks Engine

Python implementation of hooks engine
Replaces: core/hooks-engine.sh

Features:
- Event-driven hooks system
- Priority-based execution
- Pre/Post/Around hook types
- Async execution support
"""

import asyncio
import json
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Callable, Optional

from hooks.types import (
    Event,
    ExecutionContext,
    Hook,
    HookType,
    EventPriority,
    HooksConfig,
)


class HooksEngine:
    """
    Hooks Engine - Core event-driven hooks system
    """
    
    def __init__(self, config: Optional[HooksConfig] = None):
        self.config = config or HooksConfig()
        self.hooks: dict[str, list[Hook]] = {}
        self.events: dict[str, Event] = {}
        self.execution_log: list[ExecutionContext] = []
        self.initialized = False
    
    def initialize(self) -> None:
        """Initialize hooks engine"""
        self._load_config()
        self.initialized = True
        self._log("INFO", "Hooks engine initialized")
    
    def _log(self, level: str, message: str) -> None:
        """Log message"""
        timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
        log_entry = f"[{timestamp}] [HOOKS-ENGINE] [{level}] {message}"
        print(log_entry, file=sys.stderr)
    
    def _load_config(self) -> None:
        """Load configuration from file"""
        config_file = Path(os.path.expanduser("~/.oml/hooks/config.json"))
        if config_file.exists():
            try:
                with open(config_file) as f:
                    data = json.load(f)
                    self.config = HooksConfig(**data)
            except Exception as e:
                self._log("WARNING", f"Failed to load config: {e}")
    
    def register_hook(self, hook: Hook) -> None:
        """Register a hook"""
        if hook.event not in self.hooks:
            self.hooks[hook.event] = []
        
        self.hooks[hook.event].append(hook)
        # Sort by priority (lower number = higher priority)
        self.hooks[hook.event].sort(key=lambda h: h.priority)
        self._log("INFO", f"Registered hook: {hook.name} for event: {hook.event}")
    
    def unregister_hook(self, event: str, hook_name: str) -> bool:
        """Unregister a hook"""
        if event not in self.hooks:
            return False
        
        original_count = len(self.hooks[event])
        self.hooks[event] = [h for h in self.hooks[event] if h.name != hook_name]
        
        if len(self.hooks[event]) < original_count:
            self._log("INFO", f"Unregistered hook: {hook_name}")
            return True
        return False
    
    async def trigger_event(self, event_name: str, data: Optional[dict] = None) -> Event:
        """Trigger an event and execute all registered hooks"""
        event = Event(name=event_name, data=data or {})
        self.events[event_name] = event
        
        if event_name not in self.hooks:
            self._log("DEBUG", f"No hooks registered for event: {event_name}")
            return event
        
        self._log("INFO", f"Triggering event: {event_name}")
        
        for hook in self.hooks[event_name]:
            if not hook.enabled:
                continue
            
            if event.cancelled:
                self._log("DEBUG", f"Event cancelled, skipping hook: {hook.name}")
                break
            
            await self._execute_hook(hook, event)
        
        return event
    
    async def _execute_hook(self, hook: Hook, event: Event) -> ExecutionContext:
        """Execute a single hook"""
        ctx = ExecutionContext(event=event, hook=hook)
        start_time = time.time()
        
        try:
            self._log("DEBUG", f"Executing hook: {hook.name}")
            
            # Execute handler script
            result = await self._run_handler(hook.handler, event.data)
            ctx.result = result
            
        except Exception as e:
            ctx.error = str(e)
            self._log("ERROR", f"Hook {hook.name} failed: {e}")
        
        finally:
            ctx.execution_time = time.time() - start_time
            self.execution_log.append(ctx)
        
        return ctx
    
    async def _run_handler(self, handler: str, data: dict) -> Any:
        """Run hook handler script"""
        if not os.path.exists(handler):
            raise FileNotFoundError(f"Handler not found: {handler}")
        
        # Run bash script with data as JSON
        process = await asyncio.create_subprocess_exec(
            "bash", handler,
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        
        stdout, stderr = await process.communicate(
            input=json.dumps(data).encode()
        )
        
        if process.returncode != 0:
            raise RuntimeError(f"Handler failed: {stderr.decode()}")
        
        # Try to parse JSON result
        try:
            return json.loads(stdout.decode())
        except json.JSONDecodeError:
            return stdout.decode()
    
    def list_hooks(self, event: Optional[str] = None) -> list[Hook]:
        """List registered hooks"""
        if event:
            return self.hooks.get(event, [])
        
        all_hooks = []
        for hooks_list in self.hooks.values():
            all_hooks.extend(hooks_list)
        return all_hooks
    
    def get_event(self, name: str) -> Optional[Event]:
        """Get event by name"""
        return self.events.get(name)
    
    def get_execution_log(self) -> list[ExecutionContext]:
        """Get execution log"""
        return self.execution_log
    
    def enable_hook(self, event: str, hook_name: str) -> bool:
        """Enable a hook"""
        for hook in self.list_hooks(event):
            if hook.name == hook_name:
                hook.enabled = True
                self._log("INFO", f"Enabled hook: {hook_name}")
                return True
        return False
    
    def disable_hook(self, event: str, hook_name: str) -> bool:
        """Disable a hook"""
        for hook in self.list_hooks(event):
            if hook.name == hook_name:
                hook.enabled = False
                self._log("INFO", f"Disabled hook: {hook_name}")
                return True
        return False
    
    def get_stats(self) -> dict:
        """Get hooks engine statistics"""
        total_hooks = sum(len(hooks) for hooks in self.hooks.values())
        enabled_hooks = sum(
            1 for hooks in self.hooks.values() 
            for hook in hooks if hook.enabled
        )
        
        return {
            "total_hooks": total_hooks,
            "enabled_hooks": enabled_hooks,
            "disabled_hooks": total_hooks - enabled_hooks,
            "total_events": len(self.events),
            "total_executions": len(self.execution_log),
        }


# CLI interface
async def main():
    """CLI entry point"""
    engine = HooksEngine()
    engine.initialize()
    
    if len(sys.argv) < 2:
        print("OML Hooks Engine")
        print("\nUsage: python -m hooks <action> [args]")
        print("\nActions:")
        print("  register <event> <name> <handler>  Register hook")
        print("  trigger <event> [json_data]        Trigger event")
        print("  list [event]                       List hooks")
        print("  enable <event> <name>              Enable hook")
        print("  disable <event> <name>             Disable hook")
        print("  stats                              Show statistics")
        return
    
    action = sys.argv[1]
    
    if action == "register":
        if len(sys.argv) < 5:
            print("Usage: register <event> <name> <handler>")
            return
        
        hook = Hook(
            name=sys.argv[3],
            event=sys.argv[2],
            handler=sys.argv[4],
        )
        engine.register_hook(hook)
        print(f"Hook registered: {hook.name}")
    
    elif action == "trigger":
        if len(sys.argv) < 3:
            print("Usage: trigger <event> [json_data]")
            return
        
        event_name = sys.argv[2]
        data = json.loads(sys.argv[3]) if len(sys.argv) > 3 else {}
        
        event = await engine.trigger_event(event_name, data)
        print(f"Event triggered: {event.name}")
        print(f"Cancelled: {event.cancelled}")
    
    elif action == "list":
        event = sys.argv[2] if len(sys.argv) > 2 else None
        hooks = engine.list_hooks(event)
        
        print(f"Registered hooks ({len(hooks)}):")
        for hook in hooks:
            status = "✓" if hook.enabled else "✗"
            print(f"  {status} {hook.name} ({hook.event}) - {hook.handler}")
    
    elif action == "enable":
        if len(sys.argv) < 4:
            print("Usage: enable <event> <name>")
            return
        
        if engine.enable_hook(sys.argv[2], sys.argv[3]):
            print("Hook enabled")
        else:
            print("Hook not found")
    
    elif action == "disable":
        if len(sys.argv) < 4:
            print("Usage: disable <event> <name>")
            return
        
        if engine.disable_hook(sys.argv[2], sys.argv[3]):
            print("Hook disabled")
        else:
            print("Hook not found")
    
    elif action == "stats":
        stats = engine.get_stats()
        print("Hooks Engine Statistics:")
        print(f"  Total Hooks: {stats['total_hooks']}")
        print(f"  Enabled: {stats['enabled_hooks']}")
        print(f"  Disabled: {stats['disabled_hooks']}")
        print(f"  Total Events: {stats['total_events']}")
        print(f"  Total Executions: {stats['total_executions']}")
    
    else:
        print(f"Unknown action: {action}")


if __name__ == "__main__":
    asyncio.run(main())
