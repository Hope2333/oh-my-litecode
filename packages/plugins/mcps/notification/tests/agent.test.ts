import { describe, it, expect, beforeEach } from 'vitest';
import { NotificationAgent } from '../src/agent.js';

describe('NotificationAgent', () => {
  let agent: NotificationAgent;
  beforeEach(() => { agent = new NotificationAgent(); });

  it('should have correct name', () => {
    expect(agent.name).toBe('notification');
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
