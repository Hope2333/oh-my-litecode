/**
 * Context7 Agent Tests
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import { Context7Agent } from '../src/agent.js';
import { existsSync, readFileSync, writeFileSync } from 'fs';

// Mock fs module
vi.mock('fs', () => ({
  existsSync: vi.fn(),
  readFileSync: vi.fn(),
  writeFileSync: vi.fn(),
}));

describe('Context7Agent', () => {
  let agent: Context7Agent;

  beforeEach(() => {
    vi.clearAllMocks();
    agent = new Context7Agent('/tmp/test-settings.json');
  });

  describe('constructor', () => {
    it('should create agent with default config', () => {
      expect(agent.name).toBe('context7');
      expect(agent.version).toBe('0.2.0');
      expect(agent.isInitialized()).toBe(false);
    });

    it('should accept custom settings path', () => {
      const customAgent = new Context7Agent('/custom/path/settings.json');
      expect(customAgent).toBeDefined();
    });
  });

  describe('initialize', () => {
    it('should initialize with default config', async () => {
      await agent.initialize({});
      expect(agent.isInitialized()).toBe(true);
    });

    it('should initialize with custom config', async () => {
      await agent.initialize({
        mode: 'remote',
        apiKey: 'test-key',
        baseUrl: 'https://custom.url',
      });
      const config = agent.getConfig();
      expect(config.mode).toBe('remote');
      expect(config.apiKey).toBe('test-key');
    });
  });

  describe('shutdown', () => {
    it('should shutdown agent', async () => {
      await agent.initialize({});
      await agent.shutdown();
      expect(agent.isInitialized()).toBe(false);
    });
  });

  describe('enable', () => {
    it('should enable local mode', async () => {
      vi.mocked(existsSync).mockReturnValue(false);
      
      const result = await agent.enable('local');
      
      expect(result.success).toBe(true);
      expect(writeFileSync).toHaveBeenCalled();
    });

    it('should enable remote mode with API key', async () => {
      vi.mocked(existsSync).mockReturnValue(false);
      
      const result = await agent.enable('remote', 'test-key');
      
      expect(result.success).toBe(true);
    });
  });

  describe('disable', () => {
    it('should disable Context7 when enabled', async () => {
      vi.mocked(existsSync).mockReturnValue(true);
      vi.mocked(readFileSync).mockReturnValue(
        JSON.stringify({ mcpServers: { context7: { enabled: true } } })
      );
      
      const result = await agent.disable();
      
      expect(result.success).toBe(true);
      expect(writeFileSync).toHaveBeenCalled();
    });

    it('should return already disabled when not enabled', async () => {
      vi.mocked(existsSync).mockReturnValue(true);
      vi.mocked(readFileSync).mockReturnValue(
        JSON.stringify({ mcpServers: {} })
      );
      
      const result = await agent.disable();
      
      expect(result.success).toBe(true);
      expect(result.data).toEqual({ alreadyDisabled: true });
    });
  });

  describe('getStatus', () => {
    it('should return disabled status', async () => {
      vi.mocked(existsSync).mockReturnValue(false);
      
      const status = await agent.getStatus();
      
      expect(status.enabled).toBe(false);
    });

    it('should return enabled status with mode', async () => {
      vi.mocked(existsSync).mockReturnValue(true);
      vi.mocked(readFileSync).mockReturnValue(
        JSON.stringify({ mcpServers: { context7: { command: 'npx' } } })
      );
      
      const status = await agent.getStatus();
      
      expect(status.enabled).toBe(true);
      expect(status.mode).toBe('local');
    });
  });

  describe('listTools', () => {
    it('should return available tools', () => {
      const tools = agent.listTools();
      
      expect(tools).toHaveLength(2);
      expect(tools[0].name).toBe('get-library-docs');
      expect(tools[1].name).toBe('search-docs');
    });

    it('should return tools with correct schema', () => {
      const tools = agent.listTools();
      
      expect(tools[0].inputSchema.type).toBe('object');
      expect(tools[0].inputSchema.required).toContain('libraryName');
    });
  });

  describe('callTool', () => {
    it('should handle unknown tool', async () => {
      const result = await agent.callTool({ name: 'unknown-tool' });
      
      expect(result.isError).toBe(true);
      expect(result.content[0].text).toContain('Unknown tool');
    });
  });

  describe('getConfig', () => {
    it('should return config copy', async () => {
      await agent.initialize({ mode: 'remote' });
      const config = agent.getConfig();
      
      expect(config.mode).toBe('remote');
      
      // Modify returned config should not affect agent
      config.mode = 'local';
      expect(agent.getConfig().mode).toBe('remote');
    });
  });
});
