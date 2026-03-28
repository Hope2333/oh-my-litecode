/**
 * WebSearch Agent Tests
 */

import { describe, it, expect, beforeEach } from 'vitest';
import { WebSearchAgent } from '../src/agent.js';

describe('WebSearchAgent', () => {
  let agent: WebSearchAgent;

  beforeEach(() => {
    agent = new WebSearchAgent();
  });

  describe('constructor', () => {
    it('should create agent with default config', () => {
      expect(agent.name).toBe('websearch');
      expect(agent.version).toBe('0.2.0');
      expect(agent.isInitialized()).toBe(false);
    });
  });

  describe('initialize', () => {
    it('should initialize with default config', async () => {
      await agent.initialize({});
      expect(agent.isInitialized()).toBe(true);
    });

    it('should initialize with custom config', async () => {
      await agent.initialize({
        apiKey: 'test-key',
        baseUrl: 'https://custom.url',
        timeout: 60,
      });
      const config = agent.getConfig();
      expect(config.apiKey).toBe('test-key');
      expect(config.baseUrl).toBe('https://custom.url');
      expect(config.timeout).toBe(60);
    });

    it('should use environment variables', async () => {
      const originalEnv = process.env.EXA_BASE_URL;
      process.env.EXA_BASE_URL = 'https://env.url';
      
      await agent.initialize({});
      const config = agent.getConfig();
      expect(config.baseUrl).toBe('https://env.url');
      
      if (originalEnv) {
        process.env.EXA_BASE_URL = originalEnv;
      } else {
        delete process.env.EXA_BASE_URL;
      }
    });
  });

  describe('shutdown', () => {
    it('should shutdown agent', async () => {
      await agent.initialize({});
      await agent.shutdown();
      expect(agent.isInitialized()).toBe(false);
    });
  });

  describe('listTools', () => {
    it('should return available tools', () => {
      const tools = agent.listTools();
      
      expect(tools.length).toBeGreaterThanOrEqual(4);
      expect(tools.map(t => t.name)).toContain('web_search_exa');
      expect(tools.map(t => t.name)).toContain('get_code_context_exa');
      expect(tools.map(t => t.name)).toContain('web_search_advanced_exa');
      expect(tools.map(t => t.name)).toContain('crawling_exa');
    });

    it('should return tools with correct schema', () => {
      const tools = agent.listTools();
      const searchTool = tools.find(t => t.name === 'web_search_exa');
      
      expect(searchTool).toBeDefined();
      expect(searchTool!.inputSchema.type).toBe('object');
      expect(searchTool!.inputSchema.required).toContain('query');
    });
  });

  describe('callTool', () => {
    it('should handle unknown tool', async () => {
      const result = await agent.callTool({ name: 'unknown-tool' });
      
      expect(result.isError).toBe(true);
      expect(result.content[0].text).toContain('Unknown tool');
    });

    it('should handle web_search_exa without API key', async () => {
      await agent.initialize({});
      
      const result = await agent.callTool({
        name: 'web_search_exa',
        arguments: { query: 'test' },
      });
      
      expect(result.isError).toBe(true);
      expect(result.content[0].text).toContain('EXA_API_KEY');
    });

    it('should handle get_code_context_exa without API key', async () => {
      await agent.initialize({});
      
      const result = await agent.callTool({
        name: 'get_code_context_exa',
        arguments: { query: 'test' },
      });
      
      expect(result.isError).toBe(true);
    });
  });

  describe('getConfig', () => {
    it('should return config copy', async () => {
      await agent.initialize({ apiKey: 'test' });
      const config = agent.getConfig();
      
      expect(config.apiKey).toBe('test');
      
      // Modify returned config should not affect agent
      (config as { apiKey: string }).apiKey = 'modified';
      expect(agent.getConfig().apiKey).toBe('test');
    });
  });

  describe('cache management', () => {
    it('should clear cache', async () => {
      await agent.initialize({ apiKey: 'test' });
      
      // Add something to cache via search
      await agent.search({ query: 'test' });
      
      agent.clearCache();
      
      const stats = agent.getCacheStats();
      expect(stats.size).toBe(0);
    });

    it('should get cache stats', async () => {
      await agent.initialize({ apiKey: 'test' });
      
      const stats = agent.getCacheStats();
      
      expect(stats).toHaveProperty('size');
      expect(stats).toHaveProperty('entries');
    });

    it('should list sources', async () => {
      await agent.initialize({ apiKey: 'test' });
      
      const sources = agent.listSources();
      
      expect(sources).toHaveProperty('sources');
      expect(sources).toHaveProperty('total');
      expect(Array.isArray(sources.sources)).toBe(true);
    });
  });

  describe('search', () => {
    it('should return error without API key', async () => {
      await agent.initialize({});
      
      const result = await agent.search({ query: 'test' });
      
      expect(result.success).toBe(false);
      expect(result.error).toContain('EXA_API_KEY');
    });

    it('should cache results', async () => {
      await agent.initialize({ apiKey: 'test-key' });
      
      const result1 = await agent.search({ query: 'test query' });
      const result2 = await agent.search({ query: 'test query' });
      
      expect(result1.success).toBe(true);
      expect(result2.success).toBe(true);
      // Second call should use cache
    });
  });

  describe('getCodeContext', () => {
    it('should return error without API key', async () => {
      await agent.initialize({});
      
      const result = await agent.getCodeContext({ query: 'test' });
      
      expect(result.success).toBe(false);
      expect(result.error).toContain('EXA_API_KEY');
    });

    it('should cache results', async () => {
      await agent.initialize({ apiKey: 'test-key' });
      
      const result1 = await agent.getCodeContext({ query: 'test query' });
      const result2 = await agent.getCodeContext({ query: 'test query' });
      
      expect(result1.success).toBe(true);
      expect(result2.success).toBe(true);
    });
  });
});
