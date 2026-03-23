"""
Plan Agent - Task Planning and Decomposition

Features:
- Create and manage plans
- Decompose tasks into subtasks
- Analyze dependencies
- Track progress
- Export to JSON/YAML
"""

import json
import yaml
import sys
from pathlib import Path
from datetime import datetime
from typing import Optional, List, Dict, Any
from dataclasses import dataclass, field, asdict
from enum import Enum

from rich.console import Console
from rich.table import Table
from rich.tree import Tree


class TaskStatus(str, Enum):
    PENDING = "pending"
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"
    BLOCKED = "blocked"


@dataclass
class Task:
    """Represents a task in a plan"""
    id: str
    title: str
    description: str = ""
    status: TaskStatus = TaskStatus.PENDING
    dependencies: List[str] = field(default_factory=list)
    estimated_hours: float = 0.0
    actual_hours: float = 0.0
    assignee: Optional[str] = None
    tags: List[str] = field(default_factory=list)
    created_at: str = field(default_factory=lambda: datetime.now().isoformat())
    completed_at: Optional[str] = None
    
    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "title": self.title,
            "description": self.description,
            "status": self.status.value,
            "dependencies": self.dependencies,
            "estimated_hours": self.estimated_hours,
            "actual_hours": self.actual_hours,
            "assignee": self.assignee,
            "tags": self.tags,
            "created_at": self.created_at,
            "completed_at": self.completed_at,
        }


@dataclass
class Plan:
    """Represents a plan with tasks"""
    id: str
    title: str
    description: str = ""
    tasks: Dict[str, Task] = field(default_factory=dict)
    created_at: str = field(default_factory=lambda: datetime.now().isoformat())
    updated_at: str = field(default_factory=lambda: datetime.now().isoformat())
    
    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "title": self.title,
            "description": self.description,
            "tasks": {k: v.to_dict() for k, v in self.tasks.items()},
            "created_at": self.created_at,
            "updated_at": self.updated_at,
        }
    
    def add_task(self, task: Task) -> None:
        self.tasks[task.id] = task
        self.updated_at = datetime.now().isoformat()
    
    def get_task(self, task_id: str) -> Optional[Task]:
        return self.tasks.get(task_id)
    
    def update_task_status(self, task_id: str, status: TaskStatus) -> bool:
        if task_id not in self.tasks:
            return False
        task = self.tasks[task_id]
        task.status = status
        if status == TaskStatus.COMPLETED:
            task.completed_at = datetime.now().isoformat()
        self.updated_at = datetime.now().isoformat()
        return True


class PlanManager:
    """Manages plans and tasks"""
    
    def __init__(self, data_dir: Optional[Path] = None):
        self.data_dir = data_dir or Path.home() / ".oml" / "plans"
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self.console = Console()
    
    def create_plan(self, title: str, description: str = "") -> Plan:
        """Create a new plan"""
        import uuid
        plan_id = f"plan-{uuid.uuid4().hex[:8]}"
        plan = Plan(id=plan_id, title=title, description=description)
        self._save_plan(plan)
        self.console.print(f"[green]✓ Created plan:[/green] {plan_id}")
        return plan
    
    def load_plan(self, plan_id: str) -> Optional[Plan]:
        """Load a plan from disk"""
        plan_file = self.data_dir / f"{plan_id}.json"
        if not plan_file.exists():
            return None
        
        data = json.loads(plan_file.read_text())
        tasks = {}
        for task_id, task_data in data.get("tasks", {}).items():
            task = Task(
                id=task_data["id"],
                title=task_data["title"],
                description=task_data.get("description", ""),
                status=TaskStatus(task_data.get("status", "pending")),
                dependencies=task_data.get("dependencies", []),
                estimated_hours=task_data.get("estimated_hours", 0.0),
                actual_hours=task_data.get("actual_hours", 0.0),
                assignee=task_data.get("assignee"),
                tags=task_data.get("tags", []),
                created_at=task_data.get("created_at", ""),
                completed_at=task_data.get("completed_at"),
            )
            tasks[task_id] = task
        
        plan = Plan(
            id=data["id"],
            title=data["title"],
            description=data.get("description", ""),
            tasks=tasks,
            created_at=data.get("created_at", ""),
            updated_at=data.get("updated_at", ""),
        )
        return plan
    
    def _save_plan(self, plan: Plan) -> None:
        """Save plan to disk"""
        plan_file = self.data_dir / f"{plan.id}.json"
        plan_file.write_text(json.dumps(plan.to_dict(), indent=2))
    
    def list_plans(self) -> List[Dict[str, Any]]:
        """List all plans"""
        plans = []
        for plan_file in self.data_dir.glob("*.json"):
            data = json.loads(plan_file.read_text())
            plans.append({
                "id": data["id"],
                "title": data["title"],
                "tasks": len(data.get("tasks", {})),
                "updated_at": data.get("updated_at", ""),
            })
        return plans
    
    def add_task(self, plan_id: str, task: Task) -> bool:
        """Add task to plan"""
        plan = self.load_plan(plan_id)
        if not plan:
            return False
        plan.add_task(task)
        self._save_plan(plan)
        return True
    
    def decompose_task(self, plan_id: str, task_id: str, subtasks: List[Task]) -> bool:
        """Decompose a task into subtasks"""
        plan = self.load_plan(plan_id)
        if not plan or task_id not in plan.tasks:
            return False
        
        # Mark original task as completed
        plan.update_task_status(task_id, TaskStatus.COMPLETED)
        
        # Add subtasks with dependency on original task
        for subtask in subtasks:
            subtask.dependencies.append(task_id)
            plan.add_task(subtask)
        
        self._save_plan(plan)
        return True
    
    def analyze_dependencies(self, plan_id: str) -> Dict[str, Any]:
        """Analyze task dependencies and return execution order"""
        plan = self.load_plan(plan_id)
        if not plan:
            return {"error": "Plan not found"}
        
        # Topological sort
        visited = set()
        order = []
        cycles = []
        
        def visit(task_id: str, path: List[str]) -> bool:
            if task_id in path:
                cycles.append(path + [task_id])
                return False
            if task_id in visited:
                return True
            
            visited.add(task_id)
            path.append(task_id)
            
            task = plan.tasks.get(task_id)
            if task:
                for dep_id in task.dependencies:
                    if dep_id in plan.tasks:
                        visit(dep_id, path.copy())
            
            order.append(task_id)
            return True
        
        for task_id in plan.tasks:
            if task_id not in visited:
                visit(task_id, [])
        
        return {
            "execution_order": order,
            "cycles": cycles,
            "total_tasks": len(plan.tasks),
        }
    
    def export_plan(self, plan_id: str, format: str = "json") -> Optional[str]:
        """Export plan to JSON or YAML"""
        plan = self.load_plan(plan_id)
        if not plan:
            return None
        
        data = plan.to_dict()
        if format == "yaml":
            return yaml.dump(data, default_flow_style=False, sort_keys=False)
        else:
            return json.dumps(data, indent=2)
    
    def display_plan(self, plan_id: str) -> None:
        """Display plan in terminal"""
        plan = self.load_plan(plan_id)
        if not plan:
            self.console.print(f"[red]Plan not found: {plan_id}[/red]")
            return
        
        self.console.print(f"\n[bold blue]Plan: {plan.title}[/bold blue]")
        self.console.print(f"[dim]{plan.description}[/dim]\n")
        
        # Task table
        table = Table(title="Tasks")
        table.add_column("ID", style="cyan")
        table.add_column("Title", style="green")
        table.add_column("Status", style="yellow")
        table.add_column("Dependencies", style="magenta")
        table.add_column("Hours", style="blue")
        
        for task in plan.tasks.values():
            status_icon = {
                TaskStatus.PENDING: "⏳",
                TaskStatus.IN_PROGRESS: "🔄",
                TaskStatus.COMPLETED: "✅",
                TaskStatus.BLOCKED: "🚫",
            }.get(task.status, "❓")
            
            table.add_row(
                task.id,
                task.title,
                f"{status_icon} {task.status.value}",
                ", ".join(task.dependencies) or "-",
                f"{task.estimated_hours}h",
            )
        
        self.console.print(table)


def main():
    """CLI entry point"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Plan Agent - Task planning and decomposition")
    subparsers = parser.add_subparsers(dest="command", help="Commands")
    
    # Create plan
    create_parser = subparsers.add_parser("create", help="Create a new plan")
    create_parser.add_argument("title", help="Plan title")
    create_parser.add_argument("--description", "-d", default="", help="Plan description")
    
    # List plans
    subparsers.add_parser("list", help="List all plans")
    
    # Show plan
    show_parser = subparsers.add_parser("show", help="Show a plan")
    show_parser.add_argument("plan_id", help="Plan ID")
    
    # Add task
    add_task_parser = subparsers.add_parser("add-task", help="Add a task")
    add_task_parser.add_argument("plan_id", help="Plan ID")
    add_task_parser.add_argument("title", help="Task title")
    add_task_parser.add_argument("--description", "-d", default="")
    add_task_parser.add_argument("--dependencies", "--deps", default="", help="Comma-separated dependency IDs")
    add_task_parser.add_argument("--hours", "-h", type=float, default=0.0, help="Estimated hours")
    
    # Analyze dependencies
    analyze_parser = subparsers.add_parser("analyze", help="Analyze dependencies")
    analyze_parser.add_argument("plan_id", help="Plan ID")
    
    # Export
    export_parser = subparsers.add_parser("export", help="Export plan")
    export_parser.add_argument("plan_id", help="Plan ID")
    export_parser.add_argument("--format", "-f", choices=["json", "yaml"], default="json")
    export_parser.add_argument("--output", "-o", help="Output file")
    
    args = parser.parse_args()
    manager = PlanManager()
    
    if args.command == "create":
        plan = manager.create_plan(args.title, args.description)
        print(f"Plan ID: {plan.id}")
    
    elif args.command == "list":
        plans = manager.list_plans()
        if not plans:
            print("No plans found")
        else:
            for plan in plans:
                print(f"{plan['id']}: {plan['title']} ({plan['tasks']} tasks)")
    
    elif args.command == "show":
        manager.display_plan(args.plan_id)
    
    elif args.command == "add-task":
        import uuid
        task = Task(
            id=f"task-{uuid.uuid4().hex[:8]}",
            title=args.title,
            description=args.description,
            dependencies=[d.strip() for d in args.dependencies.split(",") if d.strip()],
            estimated_hours=args.hours,
        )
        if manager.add_task(args.plan_id, task):
            print(f"✓ Added task: {task.id}")
        else:
            print(f"✗ Failed to add task")
            sys.exit(1)
    
    elif args.command == "analyze":
        result = manager.analyze_dependencies(args.plan_id)
        if "error" in result:
            print(f"Error: {result['error']}")
            sys.exit(1)
        print(f"Execution order: {' -> '.join(result['execution_order'])}")
        if result['cycles']:
            print(f"Warning: Dependency cycles detected: {result['cycles']}")
    
    elif args.command == "export":
        output = manager.export_plan(args.plan_id, args.format)
        if not output:
            print("Plan not found")
            sys.exit(1)
        
        if args.output:
            Path(args.output).write_text(output)
            print(f"Exported to {args.output}")
        else:
            print(output)
    
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
