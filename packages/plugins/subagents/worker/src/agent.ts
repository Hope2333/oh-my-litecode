/**
 * Worker Subagent - Main Agent Class
 * Implements Commander-Worker architecture pattern for spawning and managing subagent tasks
 */

import type {
  WorkerConfig,
  WorkerResponse,
  TaskInfo,
  TaskStatus,
  SpawnOptions,
  LogsOptions,
} from './types.js';

export class WorkerAgent {
  public readonly name = 'worker';
  public readonly version = '0.2.0';

  private config: WorkerConfig;
  private initialized: boolean;
  private tasks: Map<string, TaskInfo>;

  constructor() {
    this.initialized = false;
    this.config = {
      maxConcurrentTasks: 5,
      taskTimeout: 3600,
      logRetention: 7,
    };
    this.tasks = new Map();
  }

  async initialize(config: Record<string, unknown>): Promise<void> {
    this.config = {
      ...this.config,
      maxConcurrentTasks: (config.maxConcurrentTasks as number) || this.config.maxConcurrentTasks,
      taskTimeout: (config.taskTimeout as number) || this.config.taskTimeout,
      logRetention: (config.logRetention as number) || this.config.logRetention,
    };
    this.initialized = true;
    console.log(`[WorkerAgent] Initialized with maxConcurrentTasks: ${this.config.maxConcurrentTasks}`);
  }

  async shutdown(): Promise<void> {
    this.initialized = false;
    console.log('[WorkerAgent] Shutdown complete');
  }

  /**
   * Spawn a new subagent task
   */
  async spawn(agent: string, options: SpawnOptions): Promise<WorkerResponse> {
    if (!this.initialized) {
      return { success: false, error: 'Agent not initialized' };
    }

    if (!options.task || options.task.trim() === '') {
      return { success: false, error: 'Task description is required' };
    }

    // Check for scope conflicts
    if (!options.force && this.hasScopeConflict(options.scope || '**')) {
      return { success: false, error: 'Scope conflicts detected. Use --force to override.' };
    }

    // Generate task ID and session ID
    const taskId = this.generateTaskId();
    const sessionId = options.sessionId || taskId;

    // Create task info
    const taskInfo: TaskInfo = {
      id: taskId,
      agent,
      task: options.task,
      scope: options.scope || '**',
      exclude: options.exclude,
      sessionId,
      createdAt: new Date().toISOString(),
      status: 'pending',
      fakeHome: `/tmp/oml-worker/${agent}-${sessionId}`,
      logFile: `/tmp/oml-worker/logs/${taskId}.log`,
    };

    // Register task
    this.tasks.set(taskId, taskInfo);

    // Simulate task spawning
    if (!options.background) {
      // Synchronous execution simulation
      taskInfo.status = 'running';
      taskInfo.startedAt = new Date().toISOString();
      
      // Simulate task completion
      setTimeout(() => {
        taskInfo.status = 'completed';
        taskInfo.completedAt = new Date().toISOString();
      }, 100);
    } else {
      // Background execution
      taskInfo.status = 'running';
      taskInfo.startedAt = new Date().toISOString();
      taskInfo.pid = Math.floor(Math.random() * 10000) + 1000;
    }

    return {
      success: true,
      taskId,
      pid: taskInfo.pid,
      content: `Spawned subagent task: ${taskId}`,
    };
  }

  /**
   * Show status of all tasks
   */
  async status(filter: string = 'all'): Promise<WorkerResponse> {
    if (!this.initialized) {
      return { success: false, error: 'Agent not initialized' };
    }

    const allTasks = Array.from(this.tasks.values());
    const filteredTasks = filter === 'all' 
      ? allTasks 
      : allTasks.filter(t => t.status === filter);

    return {
      success: true,
      content: this.formatStatus(filteredTasks),
    };
  }

  /**
   * Show logs for a task
   */
  async logs(options: LogsOptions): Promise<WorkerResponse> {
    if (!this.initialized) {
      return { success: false, error: 'Agent not initialized' };
    }

    const task = this.tasks.get(options.taskId);
    if (!task) {
      return { success: false, error: `Task not found: ${options.taskId}` };
    }

    // Simulated log content
    const logContent = `[${task.createdAt}] Task started: ${task.task}\n[${new Date().toISOString()}] Task ${task.status}`;

    return {
      success: true,
      content: logContent,
    };
  }

  /**
   * Cancel a running task
   */
  async cancel(taskId: string): Promise<WorkerResponse> {
    if (!this.initialized) {
      return { success: false, error: 'Agent not initialized' };
    }

    const task = this.tasks.get(taskId);
    if (!task) {
      return { success: false, error: `Task not found: ${taskId}` };
    }

    if (task.status === 'completed' || task.status === 'cancelled') {
      return { success: false, error: `Task already ${task.status}` };
    }

    task.status = 'cancelled';
    task.completedAt = new Date().toISOString();

    return {
      success: true,
      content: `Task cancelled: ${taskId}`,
    };
  }

  /**
   * Wait for all background tasks
   */
  async wait(): Promise<WorkerResponse> {
    if (!this.initialized) {
      return { success: false, error: 'Agent not initialized' };
    }

    const runningTasks = Array.from(this.tasks.values()).filter(t => t.status === 'running');
    
    // Simulate waiting
    for (const task of runningTasks) {
      task.status = 'completed';
      task.completedAt = new Date().toISOString();
    }

    return {
      success: true,
      content: `Waited for ${runningTasks.length} tasks to complete`,
    };
  }

  /**
   * Show detailed info about a task
   */
  async info(taskId: string): Promise<WorkerResponse> {
    if (!this.initialized) {
      return { success: false, error: 'Agent not initialized' };
    }

    const task = this.tasks.get(taskId);
    if (!task) {
      return { success: false, error: `Task not found: ${taskId}` };
    }

    return {
      success: true,
      content: JSON.stringify(task, null, 2),
    };
  }

  // Private helper methods

  private generateTaskId(): string {
    return `task-${Date.now()}-${Math.random().toString(36).substring(2, 8)}`;
  }

  private hasScopeConflict(newScope: string): boolean {
    // Check if new scope overlaps with existing running tasks
    for (const task of this.tasks.values()) {
      if (task.status === 'running' && this.scopesOverlap(task.scope, newScope)) {
        return true;
      }
    }
    return false;
  }

  private scopesOverlap(scope1: string, scope2: string): boolean {
    // Simple overlap detection
    if (scope1 === '**' || scope2 === '**') return true;
    return scope1 === scope2;
  }

  private formatStatus(tasks: TaskInfo[]): string {
    if (tasks.length === 0) {
      return 'No tasks found.';
    }

    let output = 'Subagent Tasks\n';
    output += '='.repeat(50) + '\n\n';

    for (const task of tasks) {
      output += `ID: ${task.id}\n`;
      output += `  Agent: ${task.agent}\n`;
      output += `  Task: ${task.task}\n`;
      output += `  Scope: ${task.scope}\n`;
      output += `  Status: ${task.status}\n`;
      output += `  Created: ${task.createdAt}\n`;
      if (task.pid) output += `  PID: ${task.pid}\n`;
      output += '\n';
    }

    return output;
  }

  getConfig(): WorkerConfig {
    return { ...this.config };
  }

  getTaskCount(): number {
    return this.tasks.size;
  }

  getRunningTasks(): TaskInfo[] {
    return Array.from(this.tasks.values()).filter(t => t.status === 'running');
  }
}
