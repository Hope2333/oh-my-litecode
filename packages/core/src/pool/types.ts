/**
 * Pool Types - OML Core
 * 
 * Type definitions for worker pool management.
 */

// Worker 状态
export type WorkerStatus = 'idle' | 'busy' | 'stopped' | 'failed';

// Task 状态
export type TaskStatus = 'pending' | 'running' | 'completed' | 'failed' | 'cancelled';

// Worker 接口
export interface Worker {
  id: string;
  status: WorkerStatus;
  createdAt: Date;
  startedAt?: Date;
  stoppedAt?: Date;
  currentTaskId?: string;
  completedTasks: number;
  failedTasks: number;
  metadata: Record<string, unknown>;
}

// Task 接口
export interface Task {
  id: string;
  name: string;
  status: TaskStatus;
  priority: number;
  payload: unknown;
  workerId?: string;
  createdAt: Date;
  startedAt?: Date;
  completedAt?: Date;
  result?: unknown;
  error?: string;
  retryCount: number;
  maxRetries: number;
}

// Pool 配置
export interface PoolConfig {
  minWorkers: number;
  maxWorkers: number;
  idleTimeout: number; // ms
  taskTimeout: number; // ms
  autoScale: boolean;
  scaleUpThreshold: number; // 队列长度触发扩容
  scaleDownThreshold: number; // 空闲 worker 数量触发缩容
}

// Pool 统计
export interface PoolStats {
  totalWorkers: number;
  idleWorkers: number;
  busyWorkers: number;
  pendingTasks: number;
  runningTasks: number;
  completedTasks: number;
  failedTasks: number;
  avgTaskDuration: number; // ms
}

// Worker 创建选项
export interface WorkerCreateOptions {
  metadata?: Record<string, unknown>;
}

// Task 提交选项
export interface TaskSubmitOptions {
  priority?: number;
  maxRetries?: number;
  timeout?: number;
}

// Task 结果
export interface TaskResult<T = unknown> {
  success: boolean;
  data?: T;
  error?: string;
}
