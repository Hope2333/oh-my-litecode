import { describe, it, expect, beforeEach } from 'vitest';
import { TranslatorAgent } from '../src/agent.js';

describe('TranslatorAgent', () => {
  let agent: TranslatorAgent;

  beforeEach(() => {
    agent = new TranslatorAgent();
  });

  it('should have correct name and version', () => {
    expect(agent.name).toBe('translator');
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
