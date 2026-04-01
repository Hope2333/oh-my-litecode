import { describe, it, expect, beforeEach } from 'vitest';
import { MutationTestingAgent } from '../src/agent.js';

describe('MutationTestingAgent', () => {
  let agent: MutationTestingAgent;

  beforeEach(() => { agent = new MutationTestingAgent(); });

  it('should have correct name and version', () => {
    expect(agent.name).toBe('mutation-testing');
    expect(agent.version).toBe('0.2.0');
  });

  it('should initialize with config', async () => {
    await agent.initialize({});
    expect(agent.getConfig()).toBeDefined();
  });

  it('should run mutation testing', async () => {
    await agent.initialize({});
    const result = await agent.runMutation();
    expect(result.success).toBe(true);
  });

  it('should shutdown correctly', async () => {
    await agent.initialize({});
    await agent.shutdown();
  });
});
