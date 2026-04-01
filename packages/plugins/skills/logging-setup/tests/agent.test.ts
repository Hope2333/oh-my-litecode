import { describe, it, expect, beforeEach } from 'vitest';
import { LoggingSetupAgent } from '../src/agent.js';

describe('LoggingSetupAgent', () => {
  let agent: LoggingSetupAgent;

  beforeEach(() => { agent = new LoggingSetupAgent(); });

  it('should have correct name and version', () => {
    expect(agent.name).toBe('logging-setup');
    expect(agent.version).toBe('0.2.0');
  });

  it('should initialize with config', async () => {
    await agent.initialize({});
    expect(agent.getConfig()).toBeDefined();
  });

  it('should setup logging', async () => {
    await agent.initialize({});
    const result = await agent.setupLogging();
    expect(result.success).toBe(true);
  });

  it('should shutdown correctly', async () => {
    await agent.initialize({});
    await agent.shutdown();
  });
});
