import { describe, it, expect, beforeEach } from 'vitest';
import { PerformanceTuningAgent } from '../src/agent.js';

describe('PerformanceTuningAgent', () => {
  let agent: PerformanceTuningAgent;

  beforeEach(() => { agent = new PerformanceTuningAgent(); });

  it('should have correct name and version', () => {
    expect(agent.name).toBe('performance-tuning');
    expect(agent.version).toBe('0.2.0');
  });

  it('should initialize with config', async () => {
    await agent.initialize({});
    expect(agent.getConfig()).toBeDefined();
  });

  it('should tune performance', async () => {
    await agent.initialize({});
    const result = await agent.tunePerformance();
    expect(result.success).toBe(true);
  });

  it('should shutdown correctly', async () => {
    await agent.initialize({});
    await agent.shutdown();
  });
});
