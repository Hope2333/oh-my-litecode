/**
 * Context7 MCP Agent - Main Agent Class
 * 
 * Provides MCP service for Context7 documentation lookup
 */

import { spawn } from 'child_process';
import { readFileSync, writeFileSync, existsSync } from 'fs';
import { join } from 'path';
import type { 
  Context7Config, 
  Context7Tool, 
  Context7ToolCall, 
  Context7ToolResult,
  Context7Response,
  Context7LibraryDocs,
  Context7SearchResult 
} from './types.js';

const DEFAULT_CONFIG: Context7Config = {
  mode: 'stdio',
  baseUrl: 'https://mcp.context7.com/mcp',
  localCommand: ['npx', '-y', '@upstash/context7-mcp@latest'],
};

export class Context7Agent {
  public readonly name = 'context7';
  public readonly version = '0.2.0';
  
  private config: Context7Config;
  private initialized: boolean;
  private settingsPath: string;

  constructor(settingsPath?: string) {
    this.initialized = false;
    this.config = { ...DEFAULT_CONFIG };
    this.settingsPath = settingsPath || join(process.env.HOME || '', '.qwen', 'settings.json');
  }

  async initialize(config: Record<string, unknown>): Promise<void> {
    this.config = {
      ...this.config,
      mode: (config.mode as 'local' | 'remote' | 'stdio') || 'stdio',
      apiKey: (config.apiKey as string) || process.env.CONTEXT7_API_KEY || '',
      baseUrl: (config.baseUrl as string) || 'https://mcp.context7.com/mcp',
    };
    this.initialized = true;
    console.log(`[Context7Agent] Initialized in ${this.config.mode} mode`);
  }

  async shutdown(): Promise<void> {
    this.initialized = false;
    console.log('[Context7Agent] Shutdown complete');
  }

  /**
   * Load settings from Qwen Code config
   */
  private loadSettings(): Record<string, unknown> {
    if (existsSync(this.settingsPath)) {
      try {
        return JSON.parse(readFileSync(this.settingsPath, 'utf-8'));
      } catch (error) {
        console.error('Failed to load settings:', error);
      }
    }
    return {};
  }

  /**
   * Save settings to Qwen Code config
   */
  private saveSettings(settings: Record<string, unknown>): void {
    const dir = join(this.settingsPath, '..');
    if (!existsSync(dir)) {
      // Directory creation would happen in real implementation
    }
    writeFileSync(this.settingsPath, JSON.stringify(settings, null, 2), 'utf-8');
  }

  /**
   * Enable Context7 MCP in Qwen Code settings
   */
  async enable(mode: 'local' | 'remote' = 'local', apiKey?: string): Promise<Context7Response> {
    try {
      const settings = this.loadSettings();
      const mcpServers = (settings.mcpServers as Record<string, unknown>) || {};
      
      if (mode === 'local') {
        mcpServers.context7 = {
          command: 'npx',
          args: ['-y', '@upstash/context7-mcp@latest'],
          protocol: 'mcp',
          enabled: true,
          trust: false,
        };
      } else if (mode === 'remote' && apiKey) {
        mcpServers.context7 = {
          url: 'https://mcp.context7.com/mcp',
          headers: {
            Authorization: `Bearer ${apiKey}`,
          },
          protocol: 'mcp',
          enabled: true,
        };
      }
      
      settings.mcpServers = mcpServers;
      this.saveSettings(settings);
      
      return { success: true, data: { enabled: true, mode } };
    } catch (error) {
      return { 
        success: false, 
        error: error instanceof Error ? error.message : 'Failed to enable Context7' 
      };
    }
  }

  /**
   * Disable Context7 MCP
   */
  async disable(): Promise<Context7Response> {
    try {
      const settings = this.loadSettings();
      const mcpServers = (settings.mcpServers as Record<string, unknown>) || {};
      
      if (mcpServers.context7) {
        delete mcpServers.context7;
        settings.mcpServers = mcpServers;
        this.saveSettings(settings);
        return { success: true, data: { disabled: true } };
      }
      
      return { success: true, data: { alreadyDisabled: true } };
    } catch (error) {
      return { 
        success: false, 
        error: error instanceof Error ? error.message : 'Failed to disable Context7' 
      };
    }
  }

  /**
   * Get Context7 status
   */
  async getStatus(): Promise<{ enabled: boolean; mode?: string }> {
    const settings = this.loadSettings();
    const mcpServers = (settings.mcpServers as Record<string, Record<string, unknown>>) || {};
    const context7 = mcpServers.context7;
    
    if (!context7) {
      return { enabled: false };
    }
    
    const mode = 'command' in context7 ? 'local' : 'remote';
    return { enabled: true, mode };
  }

  /**
   * Run npx command for local mode
   */
  private runNpx(args: string[]): Promise<{ stdout: string; stderr: string; code: number | null }> {
    return new Promise((resolve) => {
      const proc = spawn('npx', args, { stdio: ['pipe', 'pipe', 'pipe'] });
      let stdout = '';
      let stderr = '';
      
      proc.stdout.on('data', (data) => { stdout += data; });
      proc.stderr.on('data', (data) => { stderr += data; });
      proc.on('close', (code) => { resolve({ stdout, stderr, code }); });
    });
  }

  /**
   * Get library documentation from Context7
   */
  async getLibraryDocs(libraryName: string, query?: string): Promise<Context7Response> {
    try {
      const args = ['-y', '@upstash/context7-mcp@latest', 'get-library-docs', libraryName];
      if (query) {
        args.push(query);
      }
      
      const result = await this.runNpx(args);
      
      if (result.code !== 0) {
        return { success: false, error: result.stderr || 'Unknown error' };
      }
      
      return { success: true, data: { content: result.stdout } };
    } catch (error) {
      return { 
        success: false, 
        error: error instanceof Error ? error.message : 'Failed to get library docs' 
      };
    }
  }

  /**
   * Search Context7 documentation
   */
  async searchDocs(query: string, library?: string): Promise<Context7Response> {
    try {
      const args = ['-y', '@upstash/context7-mcp@latest', 'search-docs', query];
      if (library) {
        args.push('--library', library);
      }
      
      const result = await this.runNpx(args);
      
      if (result.code !== 0) {
        return { success: false, error: result.stderr || 'Unknown error' };
      }
      
      return { success: true, data: { content: result.stdout } };
    } catch (error) {
      return { 
        success: false, 
        error: error instanceof Error ? error.message : 'Failed to search docs' 
      };
    }
  }

  /**
   * Call a Context7 tool
   */
  async callTool(toolCall: Context7ToolCall): Promise<Context7ToolResult> {
    const { name, arguments: args } = toolCall;
    
    if (name === 'get-library-docs') {
      const libraryName = args?.libraryName as string;
      const query = args?.query as string | undefined;
      
      const result = await this.getLibraryDocs(libraryName, query);
      
      if (!result.success) {
        return {
          content: [{ type: 'text', text: `Error: ${result.error}` }],
          isError: true,
        };
      }
      
      return {
        content: [{ type: 'text', text: JSON.stringify(result.data) }],
      };
    }
    
    if (name === 'search-docs') {
      const query = args?.query as string;
      const library = args?.library as string | undefined;
      
      const result = await this.searchDocs(query, library);
      
      if (!result.success) {
        return {
          content: [{ type: 'text', text: `Error: ${result.error}` }],
          isError: true,
        };
      }
      
      return {
        content: [{ type: 'text', text: JSON.stringify(result.data) }],
      };
    }
    
    return {
      content: [{ type: 'text', text: `Unknown tool: ${name}` }],
      isError: true,
    };
  }

  /**
   * List available tools
   */
  listTools(): Context7Tool[] {
    return [
      {
        name: 'get-library-docs',
        description: 'Get documentation for a specific library from Context7',
        inputSchema: {
          type: 'object',
          properties: {
            libraryName: {
              type: 'string',
              description: 'Name of the library (e.g., "react", "vue")',
            },
            query: {
              type: 'string',
              description: 'Specific query (e.g., "hooks", "components")',
            },
          },
          required: ['libraryName'],
        },
      },
      {
        name: 'search-docs',
        description: 'Search Context7 documentation',
        inputSchema: {
          type: 'object',
          properties: {
            query: {
              type: 'string',
              description: 'Search query',
            },
            library: {
              type: 'string',
              description: 'Optional library filter',
            },
          },
          required: ['query'],
        },
      },
    ];
  }

  getConfig(): Context7Config { return { ...this.config }; }
  isInitialized(): boolean { return this.initialized; }
}
