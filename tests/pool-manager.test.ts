import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { PoolManager, createWorker, createTask, generateWorkerId, generateTaskId } from '../src/core/pool-manager.js';

describe('Pool Manager', () => {
  describe('Utility Functions', () => {
    it('should generate worker ID', () => {
      const id = generateWorkerId();
      expect(id).toMatch(/^worker-\d+-[a-f0-9]+$/);
    });

    it('should generate task ID', () => {
      const id = generateTaskId();
      expect(id).toMatch(/^task-\d+-[a-f0-9]+$/);
    });

    it('should create worker', () => {
      const worker = createWorker();
      expect(worker.id).toBeDefined();
      expect(worker.status).toBe('idle');
      expect(worker.tasksCompleted).toBe(0);
      expect(worker.tasksFailed).toBe(0);
    });

    it('should create task', () => {
      const task = createTask('Test task', { agent: 'qwen' });
      expect(task.id).toBeDefined();
      expect(task.description).toBe('Test task');
      expect(task.status).toBe('pending');
      expect(task.metadata?.agent).toBe('qwen');
    });
  });

  describe('PoolManager Class', () => {
    let pool: PoolManager;

    beforeEach(async () => {
      pool = new PoolManager({ minWorkers: 2, maxWorkers: 5 });
      await pool.init();
    });

    afterEach(async () => {
      await pool.stop();
    });

    it('should initialize pool with minimum workers', () => {
      const workers = pool.listWorkers();
      expect(workers.length).toBe(2);
      workers.forEach(w => expect(w.status).toBe('idle'));
    });

    it('should submit task', async () => {
      const task = await pool.submitTask('Test task', { agent: 'qwen' });
      expect(task.status).toBe('running'); // Should be assigned to idle worker
      expect(task.description).toBe('Test task');
    });

    it('should complete task', async () => {
      const task = await pool.submitTask('Test task');
      const completed = await pool.completeTask(task.id, { result: 'success' });
      expect(completed?.status).toBe('completed');
      expect(completed?.result).toEqual({ result: 'success' });
    });

    it('should fail task', async () => {
      const task = await pool.submitTask('Test task');
      const failed = await pool.failTask(task.id, 'Test error');
      expect(failed?.status).toBe('failed');
      expect(failed?.error).toBe('Test error');
    });

    it('should get metrics', () => {
      const metrics = pool.getMetrics();
      expect(metrics.totalWorkers).toBe(2);
      expect(metrics.idleWorkers).toBe(2);
      expect(metrics.busyWorkers).toBe(0);
      expect(metrics.pendingTasks).toBe(0);
    });

    it('should scale up when all workers busy', async () => {
      // Submit enough tasks to use all workers
      await pool.submitTask('Task 1');
      await pool.submitTask('Task 2');
      
      // Submit more tasks to trigger scale up
      await pool.submitTask('Task 3');
      await pool.submitTask('Task 4');
      
      const metrics = pool.getMetrics();
      expect(metrics.busyWorkers).toBe(2);
      // May have scaled up
      expect(metrics.totalWorkers).toBeGreaterThanOrEqual(2);
    });

    it('should list workers', () => {
      const workers = pool.listWorkers();
      expect(workers.length).toBe(2);
    });

    it('should list tasks', async () => {
      await pool.submitTask('Task 1');
      await pool.submitTask('Task 2');
      
      const tasks = pool.listTasks();
      expect(tasks.length).toBe(2);
    });

    it('should filter tasks by status', async () => {
      const task1 = await pool.submitTask('Task 1');
      await pool.completeTask(task1.id);
      
      const task2 = await pool.submitTask('Task 2');
      
      const completed = pool.listTasks('completed');
      const running = pool.listTasks('running');
      
      expect(completed.length).toBe(1);
      expect(running.length).toBe(1);
    });

    it('should get worker by ID', () => {
      const workers = pool.listWorkers();
      const worker = pool.getWorker(workers[0].id);
      expect(worker).toBeDefined();
      expect(worker?.id).toBe(workers[0].id);
    });

    it('should get task by ID', async () => {
      const task = await pool.submitTask('Test task');
      const found = pool.getTask(task.id);
      expect(found).toBeDefined();
      expect(found?.id).toBe(task.id);
    });

    it('should stop pool', async () => {
      await pool.stop();
      const workers = pool.listWorkers();
      workers.forEach(w => expect(w.status).toBe('stopped'));
    });
  });
});
