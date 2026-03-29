import { describe, it, expect, beforeEach } from 'vitest';
import { Code-reviewAgent } from '../src/agent.js';

describe('Code-reviewAgent', () => {
  let agent: Code-reviewAgent;
  beforeEach(() => { agent = new Code-reviewAgent(); });

  it('should have correct name', () => {
    expect(agent.name).toBe('code-review');
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
