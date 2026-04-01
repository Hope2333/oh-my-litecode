import { describe, it, expect, beforeEach } from 'vitest';
import { DependencyCheckAgent } from '../src/agent.js';

describe('DependencyCheckAgent', () => {
  let agent: DependencyCheckAgent;

  beforeEach(() => { agent = new DependencyCheckAgent(); });

  it('should have correct name and version', () => {
    expect(agent.name).toBe('dependency-check');
    expect(agent.version).toBe('0.2.0');
  });

  it('should initialize with config', async () => {
    await agent.initialize({});
    expect(agent.getConfig()).toBeDefined();
  });

  it('should check dependencies', async () => {
    await agent.initialize({});
    const result = await agent.checkDependencies();
    expect(result.success).toBe(true);
  });

  it('should shutdown correctly', async () => {
    await agent.initialize({});
    await agent.shutdown();
  });
});
