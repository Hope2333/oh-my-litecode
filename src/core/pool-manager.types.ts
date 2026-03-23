/**
 * OML Pool Manager Types
 * 
 * Type definitions for worker pool management
 */

export type WorkerStatus = 
  | 'idle'
  | 'busy'
  | 'stopped'
  | 'failed';

export type TaskStatus = 
  | 'pending'
  | 'running'
  | 'completed'
  | 'failed'
  | 'cancelled';

export interface Worker {
  /** Worker ID */
  id: string;
  /** Current status */
  status: WorkerStatus;
  /** Current task ID (if busy) */
  currentTaskId?: string;
  /** Created timestamp */
  createdAt: number;
  /** Last activity timestamp */
  lastActivityAt: number;
  /** Tasks completed count */
  tasksCompleted: number;
  /** Tasks failed count */
  tasksFailed: number;
  /** Metadata */
  metadata?: Record<string, unknown>;
}

export interface Task {
  /** Task ID */
  id: string;
  /** Task description */
  description: string;
  /** Assigned worker ID */
  workerId?: string;
  /** Task status */
  status: TaskStatus;
  /** Created timestamp */
  createdAt: number;
  /** Started timestamp */
  startedAt?: number;
  /** Completed timestamp */
  completedAt?: number;
  /** Result */
  result?: unknown;
  /** Error message */
  error?: string;
  /** Metadata */
  metadata?: {
    agent?: string;
    scope?: string;
    sessionId?: string;
    [key: string]: unknown;
  };
}

export interface PoolConfig {
  /** Minimum workers */
  minWorkers: number;
  /** Maximum workers */
  maxWorkers: number;
  /** Idle timeout (seconds) */
  idleTimeout: number;
  /** Task timeout (seconds) */
  taskTimeout: number;
}

export interface PoolState {
  /** Workers */
  workers: Map<string, Worker>;
  /** Tasks */
  tasks: Map<string, Task>;
  /** Pending tasks queue */
  pendingTasks: string[];
  /** Configuration */
  config: PoolConfig;
  /** Pool status */
  status: 'running' | 'stopped' | 'paused';
  /** Created timestamp */
  createdAt: number;
  /** Updated timestamp */
  updatedAt: number;
}

export interface PoolMetrics {
  /** Total workers */
  totalWorkers: number;
  /** Idle workers */
  idleWorkers: number;
  /** Busy workers */
  busyWorkers: number;
  /** Pending tasks */
  pendingTasks: number;
  /** Running tasks */
  runningTasks: number;
  /** Completed tasks (total) */
  completedTasks: number;
  /** Failed tasks (total) */
  failedTasks: number;
  /** Average task duration (ms) */
  avgTaskDuration: number;
}
