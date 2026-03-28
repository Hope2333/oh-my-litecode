import { describe, it, expect, beforeEach } from 'vitest';
import { ReviewerAgent } from '../src/agent.js';

describe('ReviewerAgent', () => {
  let agent: ReviewerAgent;

  beforeEach(() => {
    agent = new ReviewerAgent();
  });

  it('should have correct name and version', () => {
    expect(agent.name).toBe('reviewer');
    expect(agent.version).toBe('0.2.0');
  });

  it('should initialize with config', async () => {
    await agent.initialize({ maxIssues: 50, strictMode: true });
    const config = agent.getConfig();
    expect(config.maxIssues).toBe(50);
    expect(config.strictMode).toBe(true);
  });

  it('should reject code review before initialization', async () => {
    const response = await agent.code('./src');
    expect(response.success).toBe(false);
    expect(response.error).toBe('Agent not initialized');
  });

  it('should perform code review successfully', async () => {
    await agent.initialize({});
    const response = await agent.code('./src');
    expect(response.success).toBe(true);
    expect(response.content).toBeDefined();
  });

  it('should perform security audit', async () => {
    await agent.initialize({});
    const response = await agent.security('./src');
    expect(response.success).toBe(true);
  });

  it('should perform style check', async () => {
    await agent.initialize({});
    const response = await agent.style('./src');
    expect(response.success).toBe(true);
  });

  it('should perform performance analysis', async () => {
    await agent.initialize({});
    const response = await agent.performance('./src');
    expect(response.success).toBe(true);
  });

  it('should perform best practices check', async () => {
    await agent.initialize({});
    const response = await agent.bestPractices('./src');
    expect(response.success).toBe(true);
  });

  it('should generate report', async () => {
    await agent.initialize({});
    const response = await agent.report('./src');
    expect(response.success).toBe(true);
    expect(response.report).toBeDefined();
  });

  it('should return security score', async () => {
    await agent.initialize({});
    const response = await agent.security('./src', { scoreOnly: true });
    expect(response.success).toBe(true);
    expect(response.content).toContain('Security Score');
  });

  it('should format output as JSON', async () => {
    await agent.initialize({});
    const response = await agent.code('./src', { format: 'json' });
    expect(response.success).toBe(true);
    if (typeof response.content === 'string') {
      expect(() => JSON.parse(response.content)).not.toThrow();
    }
  });

  it('should format output as markdown', async () => {
    await agent.initialize({});
    const response = await agent.code('./src', { format: 'markdown' });
    expect(response.success).toBe(true);
    if (typeof response.content === 'string') {
      expect(response.content).toContain('# Code Review Report');
    }
  });

  it('should shutdown correctly', async () => {
    await agent.initialize({});
    await agent.shutdown();
    
    const response = await agent.code('./src');
    expect(response.success).toBe(false);
  });

  it('should respect disabled checks', async () => {
    await agent.initialize({ securityEnabled: false });
    const response = await agent.code('./src', { noSecurity: true });
    expect(response.success).toBe(true);
  });
});
