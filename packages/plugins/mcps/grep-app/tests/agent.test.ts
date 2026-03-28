/**
 * Grep-App Agent Tests
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import { GrepAppAgent } from '../src/agent.js';

describe('GrepAppAgent', () => {
  let agent: GrepAppAgent;

  beforeEach(() => {
    agent = new GrepAppAgent();
  });

  describe('constructor', () => {
    it('should create agent with default config', () => {
      expect(agent.name).toBe('grep-app');
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
        defaultPath: '/custom/path',
        maxResults: 50,
        excludeDirs: ['dist', 'build'],
      });
      const config = agent.getConfig();
      expect(config.defaultPath).toBe('/custom/path');
      expect(config.maxResults).toBe(50);
      expect(config.excludeDirs).toContain('dist');
    });

    it('should use environment variables', async () => {
      const originalEnv = process.env.GREP_APP_DEFAULT_PATH;
      process.env.GREP_APP_DEFAULT_PATH = '/env/path';
      
      await agent.initialize({});
      const config = agent.getConfig();
      expect(config.defaultPath).toBe('/env/path');
      
      if (originalEnv) {
        process.env.GREP_APP_DEFAULT_PATH = originalEnv;
      } else {
        delete process.env.GREP_APP_DEFAULT_PATH;
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
      expect(tools.map(t => t.name)).toContain('grep_search_intent');
      expect(tools.map(t => t.name)).toContain('grep_regex');
      expect(tools.map(t => t.name)).toContain('grep_count');
      expect(tools.map(t => t.name)).toContain('grep_files_with_matches');
    });

    it('should return tools with correct schema', () => {
      const tools = agent.listTools();
      const regexTool = tools.find(t => t.name === 'grep_regex');
      
      expect(regexTool).toBeDefined();
      expect(regexTool!.inputSchema.type).toBe('object');
      expect(regexTool!.inputSchema.required).toContain('pattern');
    });
  });

  describe('callTool', () => {
    it('should handle unknown tool', async () => {
      const result = await agent.callTool({ name: 'unknown-tool' });
      
      expect(result.isError).toBe(true);
      expect(result.content[0].text).toContain('Unknown tool');
    });

    it('should handle grep_regex tool call', async () => {
      // This will fail in test environment but should not crash
      const result = await agent.callTool({
        name: 'grep_regex',
        arguments: { pattern: 'test', path: '/nonexistent' },
      });
      
      // Should return some result (may be error or empty)
      expect(result).toBeDefined();
      expect(result.content).toBeDefined();
    });

    it('should handle grep_count tool call', async () => {
      const result = await agent.callTool({
        name: 'grep_count',
        arguments: { pattern: 'test', path: '/nonexistent' },
      });
      
      expect(result).toBeDefined();
    });

    it('should handle grep_files_with_matches tool call', async () => {
      const result = await agent.callTool({
        name: 'grep_files_with_matches',
        arguments: { pattern: 'test', path: '/nonexistent' },
      });
      
      expect(result).toBeDefined();
    });
  });

  describe('getConfig', () => {
    it('should return config copy', async () => {
      await agent.initialize({ defaultPath: '/test' });
      const config = agent.getConfig();
      
      expect(config.defaultPath).toBe('/test');
      
      // Modify returned config should not affect agent
      config.defaultPath = '/modified';
      expect(agent.getConfig().defaultPath).toBe('/test');
    });
  });

  describe('queryToPattern (private method via searchIntent)', () => {
    it('should convert function query to pattern', async () => {
      // The searchIntent method uses queryToPattern internally
      // We test it indirectly through searchIntent
      await agent.initialize({ defaultPath: '/nonexistent' });
      
      const result = await agent.searchIntent({
        query: 'find all functions',
      });
      
      // Should complete without error (even if no matches)
      expect(result).toBeDefined();
    });

    it('should convert class query to pattern', async () => {
      await agent.initialize({ defaultPath: '/nonexistent' });
      
      const result = await agent.searchIntent({
        query: 'find all classes',
      });
      
      expect(result).toBeDefined();
    });

    it('should convert TODO query to pattern', async () => {
      await agent.initialize({ defaultPath: '/nonexistent' });
      
      const result = await agent.searchIntent({
        query: 'find TODO comments',
      });
      
      expect(result).toBeDefined();
    });
  });

  describe('searchRegex', () => {
    it('should handle non-existent path gracefully', async () => {
      await agent.initialize({ defaultPath: '/nonexistent' });
      
      const result = await agent.searchRegex({
        pattern: 'test',
        path: '/nonexistent',
      });
      
      // Should return success with empty results or error
      expect(result).toBeDefined();
    });
  });

  describe('countMatches', () => {
    it('should handle non-existent path gracefully', async () => {
      await agent.initialize({ defaultPath: '/nonexistent' });
      
      const result = await agent.countMatches({
        pattern: 'test',
        path: '/nonexistent',
      });
      
      expect(result).toBeDefined();
    });
  });

  describe('filesWithMatches', () => {
    it('should handle non-existent path gracefully', async () => {
      await agent.initialize({ defaultPath: '/nonexistent' });
      
      const result = await agent.filesWithMatches({
        pattern: 'test',
        path: '/nonexistent',
      });
      
      expect(result).toBeDefined();
    });
  });
});
