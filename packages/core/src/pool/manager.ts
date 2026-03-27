/**
 * Pool Manager - OML Core
 * 
 * Worker pool management with auto-scaling support.
 */

import { EventEmitter } from 'events';
import * as fs from 'fs';
import * as path from 'path';
import type {
  Worker,
  Task,
  PoolConfig,
  PoolStats,
  WorkerStatus,
  TaskStatus,
  WorkerCreateOptions,
  TaskSubmitOptions,
  TaskResult,
} from './types.js';

export interface PoolManagerOptions {
  config?: Partial<PoolConfig>;
  workerHandler?: (worker: Worker, task: Task) => Promise<TaskResult>;
}

export class PoolManager extends EventEmitter {
  private config: PoolConfig;
  private workers: Map<string, Worker>;
  private tasks: Map<string, Task>;
  private taskQueue: Task[];
  private workerHandler: (worker: Worker, task: Task) => Promise<TaskResult>;
  private enabledPlugins: Set<string> = new Set();
  private autoScaleInterval?: NodeJS.Timeout;
  private initialized = false;

  constructor(options?: PoolManagerOptions) {
    super();
    
    this.config = {
      minWorkers: 1,
      maxWorkers: 4,
      idleTimeout: 300000, // 5 minutes
      taskTimeout: 60000, // 1 minute
      autoScale: true,
      scaleUpThreshold: 10,
      scaleDownThreshold: 2,
      ...options?.config,
    };

    this.workers = new Map();
    this.tasks = new Map();
    this.taskQueue = [];
    this.workerHandler = options?.workerHandler ?? this.defaultWorkerHandler.bind(this);
  }

  /**
   * Initialize the pool with minimum workers
   */
  async init(): Promise<void> {
    if (this.initialized) {
      return;
    }

    // Create minimum workers
    for (let i = 0; i < this.config.minWorkers; i++) {
      await this.createWorker();
    }

    // Start auto-scale if enabled
    if (this.config.autoScale) {
      this.startAutoScale();
    }

    this.initialized = true;
    this.emit('pool:init', { workerCount: this.workers.size });
  }

  /**
   * Create a new worker
   */
  async createWorker(options?: WorkerCreateOptions): Promise<Worker> {
    if (this.workers.size >= this.config.maxWorkers) {
      throw new Error(`Maximum worker count reached: ${this.config.maxWorkers}`);
    }

    const worker: Worker = {
      id: this.generateWorkerId(),
      status: 'idle',
      createdAt: new Date(),
      completedTasks: 0,
      failedTasks: 0,
      metadata: options?.metadata || {},
    };

    this.workers.set(worker.id, worker);
    this.emit('worker:create', worker);

    // Process pending tasks
    this.processQueue();

    return worker;
  }

  /**
   * Start a worker (mark as ready)
   */
  async startWorker(workerId: string): Promise<void> {
    const worker = this.getWorker(workerId);
    if (!worker) {
      throw new Error(`Worker not found: ${workerId}`);
    }

    worker.startedAt = new Date();
    worker.status = 'idle';
    
    this.emit('worker:start', worker);
    this.processQueue();
  }

  /**
   * Stop a worker
   */
  async stopWorker(workerId: string): Promise<void> {
    const worker = this.getWorker(workerId);
    if (!worker) {
      throw new Error(`Worker not found: ${workerId}`);
    }

    if (worker.status === 'busy') {
      throw new Error(`Cannot stop busy worker: ${workerId}`);
    }

    worker.status = 'stopped';
    worker.stoppedAt = new Date();
    
    this.emit('worker:stop', worker);
  }

  /**
   * Delete a worker
   */
  async deleteWorker(workerId: string): Promise<void> {
    const worker = this.getWorker(workerId);
    if (!worker) {
      throw new Error(`Worker not found: ${workerId}`);
    }

    if (worker.status === 'busy') {
      throw new Error(`Cannot delete busy worker: ${workerId}`);
    }

    this.workers.delete(workerId);
    this.emit('worker:delete', worker);
  }

  /**
   * Submit a task to the pool
   */
  async submitTask(name: string, payload: unknown, options?: TaskSubmitOptions): Promise<string> {
    const task: Task = {
      id: this.generateTaskId(),
      name,
      status: 'pending',
      priority: options?.priority ?? 0,
      payload,
      createdAt: new Date(),
      retryCount: 0,
      maxRetries: options?.maxRetries ?? 3,
    };

    this.tasks.set(task.id, task);
    this.taskQueue.push(task);
    
    // Sort by priority (higher first)
    this.taskQueue.sort((a, b) => b.priority - a.priority);

    this.emit('task:submit', task);
    this.processQueue();

    return task.id;
  }

  /**
   * Get task status
   */
  getTaskStatus(taskId: string): Task | undefined {
    return this.tasks.get(taskId);
  }

  /**
   * Get pool statistics
   */
  getStats(): PoolStats {
    const workers = Array.from(this.workers.values());
    const tasks = Array.from(this.tasks.values());

    const completedTasks = tasks.filter(t => t.status === 'completed');
    const avgDuration = completedTasks.reduce((acc, t) => {
      if (t.startedAt && t.completedAt) {
        return acc + (t.completedAt.getTime() - t.startedAt.getTime());
      }
      return acc;
    }, 0) / (completedTasks.length || 1);

    return {
      totalWorkers: workers.length,
      idleWorkers: workers.filter(w => w.status === 'idle').length,
      busyWorkers: workers.filter(w => w.status === 'busy').length,
      pendingTasks: this.taskQueue.length,
      runningTasks: tasks.filter(t => t.status === 'running').length,
      completedTasks: tasks.filter(t => t.status === 'completed').length,
      failedTasks: tasks.filter(t => t.status === 'failed').length,
      avgTaskDuration: avgDuration,
    };
  }

  /**
   * Scale up the pool
   */
  async scaleUp(count: number = 1): Promise<void> {
    for (let i = 0; i < count; i++) {
      try {
        await this.createWorker();
      } catch (error) {
        this.emit('pool:scaleError', { error, direction: 'up' });
      }
    }
  }

  /**
   * Scale down the pool
   */
  async scaleDown(count: number = 1): Promise<void> {
    const idleWorkers = Array.from(this.workers.values())
      .filter(w => w.status === 'idle')
      .slice(0, count);

    for (const worker of idleWorkers) {
      try {
        await this.stopWorker(worker.id);
        await this.deleteWorker(worker.id);
      } catch (error) {
        this.emit('pool:scaleError', { error, direction: 'down' });
      }
    }
  }

  /**
   * Shutdown the pool
   */
  async shutdown(): Promise<void> {
    // Stop auto-scale
    if (this.autoScaleInterval) {
      clearInterval(this.autoScaleInterval);
    }

    // Stop all workers
    for (const worker of this.workers.values()) {
      if (worker.status !== 'busy') {
        await this.stopWorker(worker.id);
      }
    }

    this.initialized = false;
    this.emit('pool:shutdown');
  }

  // Private methods

  private getWorker(workerId: string): Worker | undefined {
    return this.workers.get(workerId);
  }

  private getIdleWorker(): Worker | undefined {
    return Array.from(this.workers.values()).find(w => w.status === 'idle');
  }

  private async processQueue(): Promise<void> {
    while (this.taskQueue.length > 0) {
      const worker = this.getIdleWorker();
      if (!worker) {
        break;
      }

      const task = this.taskQueue.shift();
      if (!task) {
        break;
      }

      await this.assignTask(worker, task);
    }
  }

  private async assignTask(worker: Worker, task: Task): Promise<void> {
    worker.status = 'busy';
    worker.currentTaskId = task.id;
    
    task.status = 'running';
    task.startedAt = new Date();
    task.workerId = worker.id;

    this.emit('task:assign', { worker, task });

    try {
      const result = await this.workerHandler(worker, task);
      await this.completeTask(worker, task, result);
    } catch (error) {
      await this.failTask(worker, task, error instanceof Error ? error.message : String(error));
    }
  }

  private async completeTask(worker: Worker, task: Task, result: TaskResult): Promise<void> {
    worker.status = 'idle';
    worker.currentTaskId = undefined;
    worker.completedTasks++;

    task.status = result.success ? 'completed' : 'failed';
    task.completedAt = new Date();
    task.result = result.data;
    task.error = result.error;

    this.emit('task:complete', { worker, task, result });
    this.processQueue();
  }

  private async failTask(worker: Worker, task: Task, error: string): Promise<void> {
    worker.status = 'idle';
    worker.currentTaskId = undefined;
    worker.failedTasks++;

    task.retryCount++;

    if (task.retryCount < task.maxRetries) {
      // Retry
      task.status = 'pending';
      this.taskQueue.push(task);
      this.emit('task:retry', { worker, task });
    } else {
      task.status = 'failed';
      task.completedAt = new Date();
      task.error = error;
      this.emit('task:fail', { worker, task, error });
    }

    this.processQueue();
  }

  private async defaultWorkerHandler(_worker: Worker, task: Task): Promise<TaskResult> {
    // Default handler just echoes the payload
    return {
      success: true,
      data: task.payload,
    };
  }

  private startAutoScale(): void {
    this.autoScaleInterval = setInterval(() => {
      const stats = this.getStats();

      // Scale up if queue is too long
      if (stats.pendingTasks > this.config.scaleUpThreshold) {
        const needed = Math.ceil(stats.pendingTasks / this.config.scaleUpThreshold);
        this.scaleUp(Math.min(needed, this.config.maxWorkers - stats.totalWorkers));
      }

      // Scale down if too many idle workers
      if (stats.idleWorkers > this.config.scaleDownThreshold && stats.pendingTasks === 0) {
        const toRemove = Math.min(stats.idleWorkers - 1, this.config.scaleDownThreshold);
        this.scaleDown(toRemove);
      }
    }, 5000); // Check every 5 seconds
  }

  private generateWorkerId(): string {
    return `worker-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
  }

  // ========== Feature Extensions ==========

  /**
   * Save pool state to file
   */
  async saveState(filePath: string): Promise<void> {
    const state = {
      config: this.config,
      workers: Array.from(this.workers.values()),
      enabledPlugins: Array.from(this.enabledPlugins),
      savedAt: new Date().toISOString(),
    };
    const dir = path.dirname(filePath);
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(filePath, JSON.stringify(state, null, 2));
  }

  /**
   * Load pool state from file
   */
  async loadState(filePath: string): Promise<void> {
    if (!fs.existsSync(filePath)) return;
    const data = JSON.parse(fs.readFileSync(filePath, "utf-8"));
    if (data.config) this.config = { ...this.config, ...data.config };
    if (data.enabledPlugins) this.enabledPlugins = new Set(data.enabledPlugins);
  }

  private generateTaskId(): string {
    return `task-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
  }


}
