import { describe, it, expect, beforeEach } from 'vitest';
import { QwenAgent } from '../src/agent.js';

describe('QwenAgent', () => {
  let agent: QwenAgent;

  beforeEach(() => {
    agent = new QwenAgent();
  });

  it('should have correct name and version', () => {
    expect(agent.name).toBe('qwen');
    expect(agent.version).toBe('0.2.0');
  });

  it('should initialize with config', async () => {
    await agent.initialize({ apiKey: 'test-key', model: 'qwen-turbo' });
    const config = agent.getConfig();
    expect(config.apiKey).toBe('test-key');
    expect(config.model).toBe('qwen-turbo');
  });

  it('should process message after initialization', async () => {
    await agent.initialize({ apiKey: 'test-key' });
    
    const response = await agent.process({
      id: '1',
      type: 'user',
      content: 'Hello',
      timestamp: new Date(),
    });
    
    expect(response.success).toBe(true);
    expect(response.content).toContain('Hello');
  });

  it('should reject message before initialization', async () => {
    const response = await agent.process({
      id: '1',
      type: 'user',
      content: 'Hello',
      timestamp: new Date(),
    });
    
    expect(response.success).toBe(false);
    expect(response.error).toBe('Agent not initialized');
  });

  it('should shutdown correctly', async () => {
    await agent.initialize({ apiKey: 'test-key' });
    await agent.shutdown();
    
    const response = await agent.process({
      id: '1',
      type: 'user',
      content: 'Hello',
      timestamp: new Date(),
    });
    
    expect(response.success).toBe(false);
  });
});
