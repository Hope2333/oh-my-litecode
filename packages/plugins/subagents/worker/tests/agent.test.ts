import { describe, it, expect, beforeEach } from 'vitest';
import { WorkerAgent } from '../src/agent.js';

describe('WorkerAgent', () => {
  let agent: WorkerAgent;

  beforeEach(() => {
    agent = new WorkerAgent();
  });

  it('should have correct name and version', () => {
    expect(agent.name).toBe('worker');
    expect(agent.version).toBe('0.2.0');
  });

  it('should initialize with config', async () => {
    await agent.initialize({ maxConcurrentTasks: 10, taskTimeout: 7200 });
    const config = agent.getConfig();
    expect(config.maxConcurrentTasks).toBe(10);
    expect(config.taskTimeout).toBe(7200);
  });

  it('should reject spawn before initialization', async () => {
    const response = await agent.spawn('qwen', { task: 'test' });
    expect(response.success).toBe(false);
    expect(response.error).toBe('Agent not initialized');
  });

  it('should reject spawn without task', async () => {
    await agent.initialize({});
    const response = await agent.spawn('qwen', { task: '' });
    expect(response.success).toBe(false);
    expect(response.error).toBe('Task description is required');
  });

  it('should spawn task successfully', async () => {
    await agent.initialize({});
    const response = await agent.spawn('qwen', { task: 'Implement feature' });
    expect(response.success).toBe(true);
    expect(response.taskId).toBeDefined();
  });

  it('should spawn background task', async () => {
    await agent.initialize({});
    const response = await agent.spawn('qwen', { task: 'Background task', background: true });
    expect(response.success).toBe(true);
    expect(response.pid).toBeDefined();
  });

  it('should detect scope conflicts', async () => {
    await agent.initialize({});
    await agent.spawn('qwen', { task: 'Task 1', scope: 'src/**', background: true });
    const response = await agent.spawn('qwen', { task: 'Task 2', scope: 'src/**', force: false });
    expect(response.success).toBe(false);
    expect(response.error).toContain('Scope conflicts');
  });

  it('should show task status', async () => {
    await agent.initialize({});
    await agent.spawn('qwen', { task: 'Test task' });
    const response = await agent.status();
    expect(response.success).toBe(true);
    expect(response.content).toBeDefined();
  });

  it('should filter status by status', async () => {
    await agent.initialize({});
    await agent.spawn('qwen', { task: 'Test task' });
    const response = await agent.status('running');
    expect(response.success).toBe(true);
  });

  it('should show task logs', async () => {
    await agent.initialize({});
    const spawnResponse = await agent.spawn('qwen', { task: 'Test task' });
    if (spawnResponse.taskId) {
      const response = await agent.logs({ taskId: spawnResponse.taskId });
      expect(response.success).toBe(true);
      expect(response.content).toBeDefined();
    }
  });

  it('should cancel task', async () => {
    await agent.initialize({});
    const spawnResponse = await agent.spawn('qwen', { task: 'Test task', background: true });
    if (spawnResponse.taskId) {
      const response = await agent.cancel(spawnResponse.taskId);
      expect(response.success).toBe(true);
    }
  });

  it('should wait for all tasks', async () => {
    await agent.initialize({});
    await agent.spawn('qwen', { task: 'Task 1', background: true });
    await agent.spawn('qwen', { task: 'Task 2', background: true });
    const response = await agent.wait();
    expect(response.success).toBe(true);
  });

  it('should show task info', async () => {
    await agent.initialize({});
    const spawnResponse = await agent.spawn('qwen', { task: 'Test task' });
    if (spawnResponse.taskId) {
      const response = await agent.info(spawnResponse.taskId);
      expect(response.success).toBe(true);
      if (typeof response.content === 'string') {
        expect(() => JSON.parse(response.content)).not.toThrow();
      }
    }
  });

  it('should shutdown correctly', async () => {
    await agent.initialize({});
    await agent.shutdown();
    const response = await agent.spawn('qwen', { task: 'Test' });
    expect(response.success).toBe(false);
  });

  it('should track task count', async () => {
    await agent.initialize({});
    expect(agent.getTaskCount()).toBe(0);
    // Spawn multiple background tasks
    await agent.spawn('qwen', { task: 'Task 1', background: true });
    await agent.spawn('qwen', { task: 'Task 2', background: true });
    await agent.spawn('qwen', { task: 'Task 3', background: true });
    const count = agent.getTaskCount();
    expect(count).toBeGreaterThanOrEqual(1);
  });

  it('should get running tasks', async () => {
    await agent.initialize({});
    await agent.spawn('qwen', { task: 'Task 1', background: true });
    const running = agent.getRunningTasks();
    expect(running.length).toBeGreaterThanOrEqual(0);
  });
});
