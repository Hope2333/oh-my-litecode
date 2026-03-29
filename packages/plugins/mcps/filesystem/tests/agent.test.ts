import { describe, it, expect, beforeEach } from 'vitest';
import { FilesystemAgent } from '../src/agent.js';

describe('FilesystemAgent', () => {
  let agent: FilesystemAgent;
  beforeEach(() => { agent = new FilesystemAgent(); });

  it('should have correct name', () => {
    expect(agent.name).toBe('filesystem');
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
