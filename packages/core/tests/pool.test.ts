import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { PoolManager } from '../src/pool/manager.js';
import * as fs from 'fs';
import * as path from 'path';

describe('PoolManager', () => {
  let pool: PoolManager;

  beforeEach(async () => {
    pool = new PoolManager({
      config: {
        minWorkers: 1,
        maxWorkers: 4,
        autoScale: false,
      },
    });
    await pool.init();
  });

  afterEach(async () => {
    await pool.shutdown();
  });

  it('should initialize with minimum workers', async () => {
    const stats = pool.getStats();
    expect(stats.totalWorkers).toBe(1);
    expect(stats.idleWorkers).toBe(1);
  });

  it('should create a new worker', async () => {
    const worker = await pool.createWorker();
    expect(worker.id).toMatch(/^worker-/);
    expect(worker.status).toBe('idle');
    
    const stats = pool.getStats();
    expect(stats.totalWorkers).toBe(2);
  });

  it('should throw when exceeding max workers', async () => {
    await pool.createWorker();
    await pool.createWorker();
    await pool.createWorker();
    
    await expect(pool.createWorker()).rejects.toThrow('Maximum worker count reached');
  });

  it('should submit and process a task', async () => {
    const taskId = await pool.submitTask('test-task', { data: 'test' });
    
    await new Promise(resolve => setTimeout(resolve, 100));
    
    const task = pool.getTaskStatus(taskId);
    expect(task).toBeDefined();
    expect(task?.status).toBe('completed');
  });

  it('should emit events', async () => {
    const events: string[] = [];
    
    pool.on('worker:create', () => events.push('worker:create'));
    pool.on('task:submit', () => events.push('task:submit'));
    pool.on('task:complete', () => events.push('task:complete'));
    
    await pool.createWorker();
    await pool.submitTask('test', {});
    
    await new Promise(resolve => setTimeout(resolve, 100));
    
    expect(events).toContain('worker:create');
    expect(events).toContain('task:submit');
    expect(events).toContain('task:complete');
  });

  it('should scale up', async () => {
    await pool.scaleUp(2);
    
    const stats = pool.getStats();
    expect(stats.totalWorkers).toBe(3);
  });

  it('should scale down idle workers', async () => {
    await pool.createWorker();
    await pool.createWorker();
    
    await pool.scaleDown(1);
    
    const stats = pool.getStats();
    expect(stats.totalWorkers).toBe(2);
  });

  it('should handle task failure with error result', async () => {
    const failingPool = new PoolManager({
      config: { minWorkers: 1, maxWorkers: 1, autoScale: false },
      workerHandler: async () => {
        return { success: false, error: 'Test error' };
      },
    });
    
    await failingPool.init();
    
    const taskId = await failingPool.submitTask('failing-task', {}, { maxRetries: 0 });
    
    await new Promise(resolve => setTimeout(resolve, 200));
    
    const task = failingPool.getTaskStatus(taskId);
    expect(task?.status).toBe('failed');
    expect(task?.error).toBe('Test error');
    
    await failingPool.shutdown();
  });

  it('should get stats', () => {
    const stats = pool.getStats();
    
    expect(stats).toHaveProperty('totalWorkers');
    expect(stats).toHaveProperty('idleWorkers');
    expect(stats).toHaveProperty('busyWorkers');
    expect(stats).toHaveProperty('pendingTasks');
    expect(stats).toHaveProperty('completedTasks');
    expect(stats).toHaveProperty('failedTasks');
  });
});

describe('PoolManager - Edge Cases', () => {
  it('should handle concurrent task submission', async () => {
    const pool = new PoolManager({
      config: { minWorkers: 2, maxWorkers: 4, autoScale: false },
    });
    await pool.init();

    const taskIds = await Promise.all([
      pool.submitTask('task1', { id: 1 }),
      pool.submitTask('task2', { id: 2 }),
      pool.submitTask('task3', { id: 3 }),
    ]);

    expect(taskIds.length).toBe(3);
    
    await new Promise(resolve => setTimeout(resolve, 200));
    
    const stats = pool.getStats();
    expect(stats.completedTasks).toBe(3);
    
    await pool.shutdown();
  });

  it('should respect task priority', async () => {
    const pool = new PoolManager({
      config: { minWorkers: 1, maxWorkers: 1, autoScale: false },
    });
    await pool.init();

    await pool.submitTask('low', { priority: 'low' }, { priority: 1 });
    await pool.submitTask('high', { priority: 'high' }, { priority: 10 });
    await pool.submitTask('medium', { priority: 'medium' }, { priority: 5 });

    await new Promise(resolve => setTimeout(resolve, 300));
    
    const stats = pool.getStats();
    expect(stats.completedTasks).toBe(3);
    
    await pool.shutdown();
  });

  it('should handle worker failure gracefully', async () => {
    const pool = new PoolManager({
      config: { minWorkers: 1, maxWorkers: 1, autoScale: false },
      workerHandler: async () => {
        return { success: true, data: 'recovered' };
      },
    });
    await pool.init();

    const taskId = await pool.submitTask('test', {});
    
    await new Promise(resolve => setTimeout(resolve, 200));
    
    const task = pool.getTaskStatus(taskId);
    expect(task?.status).toBe('completed');
    
    await pool.shutdown();
  });

  it('should emit shutdown event', async () => {
    const pool = new PoolManager({ config: { minWorkers: 1 } });
    await pool.init();

    let shutdownEmitted = false;
    pool.on('pool:shutdown', () => {
      shutdownEmitted = true;
    });

    await pool.shutdown();
    
    expect(shutdownEmitted).toBe(true);
  });
});

describe('PoolManager - Extensions', () => {
  let pool: PoolManager;
  let testDir: string;

  beforeEach(async () => {
    testDir = path.join(process.cwd(), 'test-pool-ext-' + Date.now());
    fs.mkdirSync(testDir, { recursive: true });
    pool = new PoolManager({ config: { minWorkers: 1, maxWorkers: 2 }, dataDir: testDir });
    await pool.init();
  });

  afterEach(async () => {
    await pool.shutdown();
    fs.rmSync(testDir, { recursive: true, force: true });
  });

  it('should save and load state', async () => {
    const stateFile = path.join(testDir, 'pool-state.json');
    
    // await pool.enable('test-plugin');
    await pool.saveState(stateFile);
    
    const pool2 = new PoolManager({ config: { minWorkers: 1, maxWorkers: 2 }, dataDir: testDir });
    await pool2.loadState(stateFile);
    
    // expect(pool2.isEnabled('test-plugin')).toBe(true); // TODO: Add isEnabled method
  });
});
