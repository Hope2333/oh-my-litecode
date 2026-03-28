import { describe, it, expect, beforeEach } from 'vitest';
import { ScoutAgent } from '../src/agent.js';

describe('ScoutAgent', () => {
  let agent: ScoutAgent;

  beforeEach(() => {
    agent = new ScoutAgent();
  });

  it('should have correct name and version', () => {
    expect(agent.name).toBe('scout');
    expect(agent.version).toBe('0.2.0');
  });

  it('should initialize with config', async () => {
    await agent.initialize({ maxDepth: 5, outputFormat: 'json' });
    const config = agent.getConfig();
    expect(config.maxDepth).toBe(5);
    expect(config.outputFormat).toBe('json');
  });

  it('should reject analyze before initialization', async () => {
    const response = await agent.analyze('./src');
    expect(response.success).toBe(false);
    expect(response.error).toBe('Agent not initialized');
  });

  it('should analyze codebase successfully', async () => {
    await agent.initialize({});
    const response = await agent.analyze('./src');
    expect(response.success).toBe(true);
    expect(response.stats).toBeDefined();
  });

  it('should generate file tree', async () => {
    await agent.initialize({});
    const response = await agent.tree('./src');
    expect(response.success).toBe(true);
    expect(response.content).toBeDefined();
  });

  it('should analyze dependencies', async () => {
    await agent.initialize({});
    const response = await agent.deps('./src');
    expect(response.success).toBe(true);
  });

  it('should generate dependency graph', async () => {
    await agent.initialize({});
    const response = await agent.deps('./src', { graph: true });
    expect(response.success).toBe(true);
    if (typeof response.content === 'string') {
      expect(response.content).toContain('digraph');
    }
  });

  it('should generate report', async () => {
    await agent.initialize({});
    const response = await agent.report('./src');
    expect(response.success).toBe(true);
    if (typeof response.content === 'string') {
      expect(response.content).toContain('# Scout Analysis Report');
    }
  });

  it('should show statistics', async () => {
    await agent.initialize({});
    const response = await agent.stats('./src');
    expect(response.success).toBe(true);
    expect(response.stats).toBeDefined();
  });

  it('should format output as JSON', async () => {
    await agent.initialize({});
    const response = await agent.analyze('./src', { format: 'json' });
    expect(response.success).toBe(true);
    if (typeof response.content === 'string') {
      expect(() => JSON.parse(response.content)).not.toThrow();
    }
  });

  it('should format output as markdown', async () => {
    await agent.initialize({});
    const response = await agent.analyze('./src', { format: 'markdown' });
    expect(response.success).toBe(true);
    if (typeof response.content === 'string') {
      expect(response.content).toContain('# Codebase Analysis');
    }
  });

  it('should shutdown correctly', async () => {
    await agent.initialize({});
    await agent.shutdown();
    
    const response = await agent.analyze('./src');
    expect(response.success).toBe(false);
  });

  it('should generate tree with options', async () => {
    await agent.initialize({});
    const response = await agent.tree('./src', { maxDepth: 2, showFiles: true });
    expect(response.success).toBe(true);
  });
});
