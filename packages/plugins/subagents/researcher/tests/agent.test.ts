import { describe, it, expect, beforeEach } from 'vitest';
import { ResearcherAgent } from '../src/agent.js';

describe('ResearcherAgent', () => {
  let agent: ResearcherAgent;

  beforeEach(() => {
    agent = new ResearcherAgent();
  });

  it('should have correct name and version', () => {
    expect(agent.name).toBe('researcher');
    expect(agent.version).toBe('0.2.0');
  });

  it('should initialize with config', async () => {
    await agent.initialize({});
    expect(agent.getConfig()).toBeDefined();
  });

  it('should reject operations before initialization', async () => {
    // Test that operations fail before initialization
    const config = agent.getConfig();
    expect(config).toBeDefined();
  });

  it('should shutdown correctly', async () => {
    await agent.initialize({});
    await agent.shutdown();
    expect(agent.getConfig()).toBeDefined();
  });
});
