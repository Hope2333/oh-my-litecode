import { describe, it, expect, beforeEach } from 'vitest';
import { Performance-analysisAgent } from '../src/agent.js';

describe('Performance-analysisAgent', () => {
  let agent: Performance-analysisAgent;
  beforeEach(() => { agent = new Performance-analysisAgent(); });

  it('should have correct name', () => {
    expect(agent.name).toBe('performance-analysis');
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
