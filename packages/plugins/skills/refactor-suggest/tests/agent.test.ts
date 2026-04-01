import { describe, it, expect, beforeEach } from 'vitest';
import { RefactorSuggestAgent } from '../src/agent.js';

describe('RefactorSuggestAgent', () => {
  let agent: RefactorSuggestAgent;

  beforeEach(() => { agent = new RefactorSuggestAgent(); });

  it('should have correct name and version', () => {
    expect(agent.name).toBe('refactor-suggest');
    expect(agent.version).toBe('0.2.0');
  });

  it('should initialize with config', async () => {
    await agent.initialize({});
    expect(agent.getConfig()).toBeDefined();
  });

  it('should analyze code', async () => {
    await agent.initialize({});
    const result = await agent.analyzeCode('./src');
    expect(result.success).toBe(true);
  });

  it('should shutdown correctly', async () => {
    await agent.initialize({});
    await agent.shutdown();
  });
});
