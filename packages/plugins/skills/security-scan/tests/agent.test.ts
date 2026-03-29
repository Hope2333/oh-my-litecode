import { describe, it, expect, beforeEach } from 'vitest';
import { Security-scanAgent } from '../src/agent.js';

describe('Security-scanAgent', () => {
  let agent: Security-scanAgent;
  beforeEach(() => { agent = new Security-scanAgent(); });

  it('should have correct name', () => {
    expect(agent.name).toBe('security-scan');
  });

  it('should initialize', async () => {
    await agent.initialize({});
    const response = await agent.process({ id: '1', type: 'user', content: 'test', timestamp: new Date() });
    expect(response.success).toBe(true);
  });

  it('should reject before initialization', async () => {
    const response = await agent.process({ id: '1', type: 'user', content: 'test', timestamp: new Date() });
    expect(response.success).toBe(false);
  });
});
