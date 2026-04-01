import { describe, it, expect, beforeEach } from 'vitest';
import { ErrorHandlingAgent } from '../src/agent.js';

describe('ErrorHandlingAgent', () => {
  let agent: ErrorHandlingAgent;

  beforeEach(() => { agent = new ErrorHandlingAgent(); });

  it('should have correct name and version', () => {
    expect(agent.name).toBe('error-handling');
    expect(agent.version).toBe('0.2.0');
  });

  it('should initialize with config', async () => {
    await agent.initialize({});
    expect(agent.getConfig()).toBeDefined();
  });

  it('should check error handling', async () => {
    await agent.initialize({});
    const result = await agent.checkErrorHandling('./src');
    expect(result.success).toBe(true);
  });

  it('should shutdown correctly', async () => {
    await agent.initialize({});
    await agent.shutdown();
  });
});
