import { describe, it, expect, beforeEach } from 'vitest';
import { Documentation-genAgent } from '../src/agent.js';

describe('Documentation-genAgent', () => {
  let agent: Documentation-genAgent;
  beforeEach(() => { agent = new Documentation-genAgent(); });

  it('should have correct name', () => {
    expect(agent.name).toBe('documentation-gen');
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
