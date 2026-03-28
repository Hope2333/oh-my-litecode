/**
 * Worker Subagent Types
 */

export type TaskStatus = 'pending' | 'running' | 'completed' | 'failed' | 'cancelled';

export interface WorkerConfig {
  maxConcurrentTasks: number;
  taskTimeout: number;
  logRetention: number;
}

export interface TaskDefinition {
  id: string;
  agent: string;
  task: string;
  scope: string;
  exclude?: string;
  sessionId: string;
  createdAt: string;
}

export interface TaskInfo extends TaskDefinition {
  status: TaskStatus;
  pid?: number;
  logFile?: string;
  fakeHome?: string;
  startedAt?: string;
  completedAt?: string;
  error?: string;
}

export interface SpawnOptions {
  task: string;
  scope?: string;
  exclude?: string;
  background?: boolean;
  force?: boolean;
  sessionId?: string;
}

export interface LogsOptions {
  taskId: string;
  follow?: boolean;
  lines?: number;
}

export interface WorkerResponse {
  success: boolean;
  content?: string | TaskInfo | TaskInfo[];
  error?: string;
  taskId?: string;
  pid?: number;
}
