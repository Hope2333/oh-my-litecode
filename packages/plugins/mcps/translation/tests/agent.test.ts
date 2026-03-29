import { describe, it, expect, beforeEach } from 'vitest';
import { TranslationAgent } from '../src/agent.js';

describe('TranslationAgent', () => {
  let agent: TranslationAgent;
  beforeEach(() => { agent = new TranslationAgent(); });

  it('should have correct name', () => {
    expect(agent.name).toBe('translation');
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
