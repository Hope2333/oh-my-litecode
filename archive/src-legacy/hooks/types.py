"""
OML Hooks Types

Type definitions for hooks system
"""

from dataclasses import dataclass, field
from typing import Any, Callable, Optional
from enum import Enum
import time


class HookType(str, Enum):
    """Hook execution type"""
    PRE = "pre"
    POST = "post"
    AROUND = "around"


class EventPriority(int, Enum):
    """Event priority levels"""
    CRITICAL = 0
    HIGH = 50
    NORMAL = 100
    LOW = 150


@dataclass
class Hook:
    """Represents a registered hook"""
    name: str
    event: str
    handler: str  # Path to handler script
    priority: int = EventPriority.NORMAL
    enabled: bool = True
    hook_type: HookType = HookType.POST
    description: str = ""
    created_at: float = field(default_factory=time.time)
    
    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "event": self.event,
            "handler": self.handler,
            "priority": self.priority,
            "enabled": self.enabled,
            "hook_type": self.hook_type.value,
            "description": self.description,
            "created_at": self.created_at,
        }


@dataclass
class Event:
    """Represents an event"""
    name: str
    data: dict = field(default_factory=dict)
    timestamp: float = field(default_factory=time.time)
    result: Any = None
    cancelled: bool = False
    
    def cancel(self) -> None:
        """Cancel event propagation"""
        self.cancelled = True
    
    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "data": self.data,
            "timestamp": self.timestamp,
            "result": self.result,
            "cancelled": self.cancelled,
        }


@dataclass
class ExecutionContext:
    """Execution context for hooks"""
    event: Event
    hook: Hook
    result: Any = None
    error: Optional[str] = None
    execution_time: float = 0.0


@dataclass
class HooksConfig:
    """Hooks system configuration"""
    enabled: bool = True
    log_level: str = "INFO"
    timeout: int = 300  # seconds
    max_retries: int = 3
    log_file: str = "~/.oml/hooks.log"
    
    def to_dict(self) -> dict:
        return {
            "enabled": self.enabled,
            "log_level": self.log_level,
            "timeout": self.timeout,
            "max_retries": self.max_retries,
            "log_file": self.log_file,
        }
