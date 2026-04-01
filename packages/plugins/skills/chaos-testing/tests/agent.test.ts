import { describe, it, expect, beforeEach } from 'vitest';
import { ChaosTestingAgent } from '../src/agent.js';

describe('ChaosTestingAgent', () => {
  let agent: ChaosTestingAgent;

  beforeEach(() => { agent = new ChaosTestingAgent(); });

  it('should have correct name and version', () => {
    expect(agent.name).toBe('chaos-testing');
    expect(agent.version).toBe('0.2.0');
  });

  it('should initialize with config', async () => {
    await agent.initialize({});
    expect(agent.getConfig()).toBeDefined();
  });

  it('should run chaos testing', async () => {
    await agent.initialize({});
    const result = await agent.runChaos();
    expect(result.success).toBe(true);
  });

  it('should shutdown correctly', async () => {
    await agent.initialize({});
    await agent.shutdown();
  });
});
