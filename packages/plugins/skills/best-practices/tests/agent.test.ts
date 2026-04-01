import { describe, it, expect, beforeEach } from 'vitest';
import { BestPracticesAgent } from '../src/agent.js';

describe('BestPracticesAgent', () => {
  let agent: BestPracticesAgent;

  beforeEach(() => { agent = new BestPracticesAgent(); });

  it('should have correct name and version', () => {
    expect(agent.name).toBe('best-practices');
    expect(agent.version).toBe('0.2.0');
  });

  it('should initialize with config', async () => {
    await agent.initialize({});
    expect(agent.getConfig()).toBeDefined();
  });

  it('should check best practices', async () => {
    await agent.initialize({});
    const result = await agent.checkBestPractices('./src');
    expect(result.success).toBe(true);
  });

  it('should shutdown correctly', async () => {
    await agent.initialize({});
    await agent.shutdown();
  });
});
