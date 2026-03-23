/**
 * OML Worker Pool Manager
 * 
 * TypeScript implementation of worker pool management
 * Replaces: core/pool-manager.sh (simplified version)
 * 
 * Features:
 * - Worker lifecycle management
 * - Task scheduling
 * - Auto-scaling
 * - Metrics collection
 */

import * as fs from 'fs';
import * as path from 'path';
import * as crypto from 'crypto';
import type {
  Worker,
  Task,
  PoolConfig,
  PoolState,
  PoolMetrics,
  WorkerStatus,
  TaskStatus,
} from './pool-manager.types';

/**
 * Get pool directory
 */
export function getPoolDir(): string {
  const omlRoot = process.env.OML_ROOT || path.resolve(__dirname, '../../');
  const poolDir = path.join(omlRoot, '.oml', 'pool');
  
  if (!fs.existsSync(poolDir)) {
    fs.mkdirSync(poolDir, { recursive: true });
  }
  
  return poolDir;
}

/**
 * Generate unique worker ID
 */
export function generateWorkerId(): string {
  const timestamp = Date.now();
  const random = crypto.randomBytes(8).toString('hex');
  return `worker-${timestamp}-${random}`;
}

/**
 * Generate unique task ID
 */
export function generateTaskId(): string {
  const timestamp = Date.now();
  const random = crypto.randomBytes(4).toString('hex');
  return `task-${timestamp}-${random}`;
}

/**
 * Create a new worker
 */
export function createWorker(): Worker {
  const now = Date.now();
  
  return {
    id: generateWorkerId(),
    status: 'idle',
    createdAt: now,
    lastActivityAt: now,
    tasksCompleted: 0,
    tasksFailed: 0,
  };
}

/**
 * Create a new task
 */
export function createTask(
  description: string,
  metadata?: { agent?: string; scope?: string; sessionId?: string }
): Task {
  return {
    id: generateTaskId(),
    description,
    status: 'pending',
    createdAt: Date.now(),
    metadata,
  };
}

/**
 * Pool Manager Class
 */
export class PoolManager {
  private workers: Map<string, Worker> = new Map();
  private tasks: Map<string, Task> = new Map();
  private pendingTasks: string[] = [];
  private config: PoolConfig;
  private state: PoolState;
  private timer?: NodeJS.Timeout;

  constructor(config?: Partial<PoolConfig>) {
    this.config = {
      minWorkers: config?.minWorkers || 1,
      maxWorkers: config?.maxWorkers || 10,
      idleTimeout: config?.idleTimeout || 300,
      taskTimeout: config?.taskTimeout || 600,
    };

    this.state = {
      workers: this.workers,
      tasks: this.tasks,
      pendingTasks: this.pendingTasks,
      config: this.config,
      status: 'stopped',
      createdAt: Date.now(),
      updatedAt: Date.now(),
    };
  }

  /**
   * Initialize pool
   */
  async init(): Promise<void> {
    // Create minimum workers
    for (let i = 0; i < this.config.minWorkers; i++) {
      const worker = createWorker();
      this.workers.set(worker.id, worker);
    }
    
    this.state.status = 'running';
    this.state.updatedAt = Date.now();
    
    // Start auto-scaling monitor
    this.startMonitor();
  }

  /**
   * Start auto-scaling monitor
   */
  private startMonitor(): void {
    this.timer = setInterval(() => {
      this.autoScale();
      this.cleanupIdleWorkers();
    }, 5000); // Check every 5 seconds
  }

  /**
   * Stop pool
   */
  async stop(): Promise<void> {
    if (this.timer) {
      clearInterval(this.timer);
    }
    
    // Stop all workers
    for (const worker of this.workers.values()) {
      worker.status = 'stopped';
    }
    
    this.state.status = 'stopped';
    this.state.updatedAt = Date.now();
  }

  /**
   * Submit task to pool
   */
  async submitTask(
    description: string,
    metadata?: { agent?: string; scope?: string; sessionId?: string }
  ): Promise<Task> {
    const task = createTask(description, metadata);
    this.tasks.set(task.id, task);
    this.pendingTasks.push(task.id);
    
    // Try to assign to idle worker
    this.assignPendingTasks();
    
    return task;
  }

  /**
   * Assign pending tasks to idle workers
   */
  private assignPendingTasks(): void {
    for (const worker of this.workers.values()) {
      if (worker.status !== 'idle') continue;
      if (this.pendingTasks.length === 0) break;
      
      const taskId = this.pendingTasks.shift()!;
      const task = this.tasks.get(taskId);
      
      if (!task) continue;
      
      // Assign task to worker
      task.status = 'running';
      task.startedAt = Date.now();
      task.workerId = worker.id;
      
      worker.status = 'busy';
      worker.currentTaskId = task.id;
      worker.lastActivityAt = Date.now();
    }
  }

  /**
   * Complete task
   */
  async completeTask(taskId: string, result?: unknown): Promise<Task | null> {
    const task = this.tasks.get(taskId);
    if (!task) return null;
    
    task.status = 'completed';
    task.completedAt = Date.now();
    task.result = result;
    
    // Free worker
    if (task.workerId) {
      const worker = this.workers.get(task.workerId);
      if (worker) {
        worker.status = 'idle';
        worker.currentTaskId = undefined;
        worker.tasksCompleted++;
        worker.lastActivityAt = Date.now();
      }
    }
    
    // Assign next pending task
    this.assignPendingTasks();
    
    return task;
  }

  /**
   * Fail task
   */
  async failTask(taskId: string, error: string): Promise<Task | null> {
    const task = this.tasks.get(taskId);
    if (!task) return null;
    
    task.status = 'failed';
    task.completedAt = Date.now();
    task.error = error;
    
    // Free worker
    if (task.workerId) {
      const worker = this.workers.get(task.workerId);
      if (worker) {
        worker.status = 'idle';
        worker.currentTaskId = undefined;
        worker.tasksFailed++;
        worker.lastActivityAt = Date.now();
      }
    }
    
    return task;
  }

  /**
   * Auto-scale workers
   */
  private autoScale(): void {
    const metrics = this.getMetrics();
    
    // Scale up if all workers busy and have pending tasks
    if (metrics.busyWorkers === metrics.totalWorkers && metrics.pendingTasks > 0) {
      if (metrics.totalWorkers < this.config.maxWorkers) {
        const worker = createWorker();
        this.workers.set(worker.id, worker);
        this.assignPendingTasks();
      }
    }
  }

  /**
   * Cleanup idle workers
   */
  private cleanupIdleWorkers(): void {
    const now = Date.now();
    
    for (const [id, worker] of this.workers.entries()) {
      if (worker.status !== 'idle') continue;
      if (this.workers.size <= this.config.minWorkers) continue;
      
      const idleTime = (now - worker.lastActivityAt) / 1000;
      if (idleTime > this.config.idleTimeout) {
        this.workers.delete(id);
      }
    }
  }

  /**
   * Get pool metrics
   */
  getMetrics(): PoolMetrics {
    const workers = Array.from(this.workers.values());
    const tasks = Array.from(this.tasks.values());
    
    const idleWorkers = workers.filter(w => w.status === 'idle').length;
    const busyWorkers = workers.filter(w => w.status === 'busy').length;
    const completedTasks = tasks.filter(t => t.status === 'completed').length;
    const failedTasks = tasks.filter(t => t.status === 'failed').length;
    const runningTasks = tasks.filter(t => t.status === 'running').length;
    
    // Calculate average task duration
    const completedTaskDurations = tasks
      .filter(t => t.status === 'completed' && t.startedAt && t.completedAt)
      .map(t => (t.completedAt! - t.startedAt!));
    
    const avgTaskDuration = completedTaskDurations.length > 0
      ? completedTaskDurations.reduce((a, b) => a + b, 0) / completedTaskDurations.length
      : 0;
    
    return {
      totalWorkers: workers.length,
      idleWorkers,
      busyWorkers,
      pendingTasks: this.pendingTasks.length,
      runningTasks,
      completedTasks,
      failedTasks,
      avgTaskDuration,
    };
  }

  /**
   * Get worker by ID
   */
  getWorker(id: string): Worker | undefined {
    return this.workers.get(id);
  }

  /**
   * Get task by ID
   */
  getTask(id: string): Task | undefined {
    return this.tasks.get(id);
  }

  /**
   * List workers
   */
  listWorkers(): Worker[] {
    return Array.from(this.workers.values());
  }

  /**
   * List tasks
   */
  listTasks(status?: TaskStatus): Task[] {
    const tasks = Array.from(this.tasks.values());
    if (status) {
      return tasks.filter(t => t.status === status);
    }
    return tasks;
  }

  /**
   * Get state
   */
  getState(): PoolState {
    return this.state;
  }
}

// CLI export
if (import.meta.url === `file://${process.argv[1]}`) {
  const action = process.argv[2] || 'status';
  
  (async () => {
    const pool = new PoolManager();
    
    switch (action) {
      case 'init':
        await pool.init();
        console.log('Pool initialized');
        console.log(`Workers: ${pool.listWorkers().length}`);
        break;
        
      case 'submit':
        await pool.init();
        const task = await pool.submitTask(
          process.argv[3] || 'Test task',
          { agent: process.argv[4] || 'qwen' }
        );
        console.log(`Task submitted: ${task.id}`);
        break;
        
      case 'status':
        await pool.init();
        const metrics = pool.getMetrics();
        console.log('Pool Metrics:');
        console.log(`  Total Workers: ${metrics.totalWorkers}`);
        console.log(`  Idle Workers: ${metrics.idleWorkers}`);
        console.log(`  Busy Workers: ${metrics.busyWorkers}`);
        console.log(`  Pending Tasks: ${metrics.pendingTasks}`);
        console.log(`  Running Tasks: ${metrics.runningTasks}`);
        console.log(`  Completed Tasks: ${metrics.completedTasks}`);
        console.log(`  Failed Tasks: ${metrics.failedTasks}`);
        break;
        
      case 'workers':
        await pool.init();
        const workers = pool.listWorkers();
        console.log(`Workers (${workers.length}):`);
        for (const worker of workers) {
          console.log(`  ${worker.id} | ${worker.status} | Completed: ${worker.tasksCompleted}`);
        }
        break;
        
      case 'tasks':
        await pool.init();
        const tasks = pool.listTasks();
        console.log(`Tasks (${tasks.length}):`);
        for (const task of tasks) {
          console.log(`  ${task.id} | ${task.status} | ${task.description}`);
        }
        break;
        
      case 'stop':
        await pool.stop();
        console.log('Pool stopped');
        break;
        
      default:
        console.log('OML Pool Manager');
        console.log('\nUsage: pool-manager <action> [args]');
        console.log('\nActions:');
        console.log('  init              Initialize pool');
        console.log('  submit <desc>     Submit task');
        console.log('  status            Show pool metrics');
        console.log('  workers           List workers');
        console.log('  tasks             List tasks');
        console.log('  stop              Stop pool');
    }
  })();
}
