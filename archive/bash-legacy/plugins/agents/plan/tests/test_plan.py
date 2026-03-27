"""Tests for Plan Agent"""

import json
import pytest
from pathlib import Path
from tempfile import TemporaryDirectory

import sys
sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from plan_agent import (
    PlanManager, Plan, Task, TaskStatus,
)


class TestTask:
    """Test Task model"""
    
    def test_create_task(self):
        task = Task(id="task-1", title="Test Task")
        assert task.id == "task-1"
        assert task.status == TaskStatus.PENDING
        assert task.dependencies == []
    
    def test_task_to_dict(self):
        task = Task(id="task-1", title="Test", estimated_hours=2.0)
        data = task.to_dict()
        assert data["id"] == "task-1"
        assert data["estimated_hours"] == 2.0


class TestPlan:
    """Test Plan model"""
    
    def test_create_plan(self):
        plan = Plan(id="plan-1", title="Test Plan")
        assert plan.id == "plan-1"
        assert plan.tasks == {}
    
    def test_add_task(self):
        plan = Plan(id="plan-1", title="Test")
        task = Task(id="task-1", title="Task 1")
        plan.add_task(task)
        assert len(plan.tasks) == 1
        assert plan.get_task("task-1") == task
    
    def test_update_task_status(self):
        plan = Plan(id="plan-1", title="Test")
        task = Task(id="task-1", title="Task 1")
        plan.add_task(task)
        
        assert plan.update_task_status("task-1", TaskStatus.IN_PROGRESS)
        assert plan.tasks["task-1"].status == TaskStatus.IN_PROGRESS
        
        assert plan.update_task_status("task-1", TaskStatus.COMPLETED)
        assert plan.tasks["task-1"].status == TaskStatus.COMPLETED
        assert plan.tasks["task-1"].completed_at is not None


class TestPlanManager:
    """Test PlanManager"""
    
    @pytest.fixture
    def manager(self):
        with TemporaryDirectory() as tmpdir:
            yield PlanManager(data_dir=Path(tmpdir))
    
    def test_create_plan(self, manager):
        plan = manager.create_plan("Test Plan", "Test description")
        assert plan.id.startswith("plan-")
        assert plan.title == "Test Plan"
        
        # Verify saved to disk
        loaded = manager.load_plan(plan.id)
        assert loaded is not None
        assert loaded.title == "Test Plan"
    
    def test_list_plans(self, manager):
        plan1 = manager.create_plan("Plan 1")
        plan2 = manager.create_plan("Plan 2")
        
        plans = manager.list_plans()
        assert len(plans) == 2
    
    def test_add_task(self, manager):
        plan = manager.create_plan("Test")
        task = Task(id="task-1", title="Task 1")
        
        assert manager.add_task(plan.id, task)
        
        loaded = manager.load_plan(plan.id)
        assert loaded is not None
        assert "task-1" in loaded.tasks
    
    def test_analyze_dependencies(self, manager):
        plan = manager.create_plan("Test")
        
        # Add tasks with dependencies
        task1 = Task(id="task-1", title="Task 1")
        task2 = Task(id="task-2", title="Task 2", dependencies=["task-1"])
        task3 = Task(id="task-3", title="Task 3", dependencies=["task-2"])
        
        manager.add_task(plan.id, task1)
        manager.add_task(plan.id, task2)
        manager.add_task(plan.id, task3)
        
        result = manager.analyze_dependencies(plan.id)
        assert "execution_order" in result
        # task-1 should come before task-2, task-2 before task-3
        order = result["execution_order"]
        assert order.index("task-1") < order.index("task-2")
        assert order.index("task-2") < order.index("task-3")
    
    def test_export_json(self, manager):
        plan = manager.create_plan("Test")
        manager.add_task(plan.id, Task(id="task-1", title="Task 1"))
        
        output = manager.export_plan(plan.id, "json")
        assert output is not None
        data = json.loads(output)
        assert data["title"] == "Test"
    
    def test_export_yaml(self, manager):
        plan = manager.create_plan("Test")
        manager.add_task(plan.id, Task(id="task-1", title="Task 1"))
        
        output = manager.export_plan(plan.id, "yaml")
        assert output is not None
        assert "title: Test" in output
