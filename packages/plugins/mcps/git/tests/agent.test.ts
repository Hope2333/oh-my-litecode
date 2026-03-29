import { describe, it, expect, beforeEach } from 'vitest';
import { GitAgent } from '../src/agent.js';

describe('GitAgent', () => {
  let agent: GitAgent;
  beforeEach(() => { agent = new GitAgent(); });

  it('should have correct name', () => {
    expect(agent.name).toBe('git');
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
