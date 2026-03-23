/**
 * Context7 MCP Service - TypeScript Implementation
 * 
 * Provides MCP (Model Context Protocol) service for Context7 documentation
 * 
 * Usage:
 *   # Local mode (runs npx @upstash/context7-mcp)
 *   node dist/index.js --mode local
 *   
 *   # Remote mode (uses Context7 API)
 *   node dist/index.js --mode remote --api-key "sk-xxx"
 *   
 *   # MCP stdio mode (for Qwen Code integration)
 *   node dist/index.js --mode stdio
 */

import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from '@modelcontextprotocol/sdk/types.js';
import { spawn } from 'child_process';
import { readFileSync, writeFileSync, existsSync } from 'fs';
import { join } from 'path';

// Configuration
interface Context7Config {
  mode: 'local' | 'remote' | 'stdio';
  apiKey?: string;
  baseUrl?: string;
}

const DEFAULT_CONFIG: Context7Config = {
  mode: 'stdio',
  baseUrl: 'https://mcp.context7.com/mcp',
};

// Load settings from Qwen Code config
function loadSettings(settingsPath?: string): Record<string, unknown> {
  const path = settingsPath || join(process.env.HOME || '', '.qwen', 'settings.json');
  if (existsSync(path)) {
    try {
      return JSON.parse(readFileSync(path, 'utf-8'));
    } catch (error) {
      console.error('Failed to load settings:', error);
    }
  }
  return {};
}

// Save settings
function saveSettings(settings: Record<string, unknown>, settingsPath?: string): void {
  const path = settingsPath || join(process.env.HOME || '', '.qwen', 'settings.json');
  writeFileSync(path, JSON.stringify(settings, null, 2), 'utf-8');
}

// Enable Context7 MCP in Qwen Code settings
async function enableContext7(mode: 'local' | 'remote' = 'local', apiKey?: string): Promise<void> {
  const settings = loadSettings();
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
  saveSettings(settings);
  console.log(`Context7 MCP enabled (${mode} mode)`);
}

// Disable Context7 MCP
async function disableContext7(): Promise<void> {
  const settings = loadSettings();
  const mcpServers = (settings.mcpServers as Record<string, unknown>) || {};
  
  if (mcpServers.context7) {
    delete mcpServers.context7;
    settings.mcpServers = mcpServers;
    saveSettings(settings);
    console.log('Context7 MCP disabled');
  } else {
    console.log('Context7 MCP not enabled');
  }
}

// Get Context7 status
async function getStatus(): Promise<{ enabled: boolean; mode?: string }> {
  const settings = loadSettings();
  const mcpServers = (settings.mcpServers as Record<string, Record<string, unknown>>) || {};
  const context7 = mcpServers.context7;
  
  if (!context7) {
    return { enabled: false };
  }
  
  const mode = 'command' in context7 ? 'local' : 'remote';
  return { enabled: true, mode };
}

// Run npx command for local mode
function runNpx(args: string[]): Promise<{ stdout: string; stderr: string; code: number | null }> {
  return new Promise((resolve) => {
    const proc = spawn('npx', args, { stdio: ['pipe', 'pipe', 'pipe'] });
    let stdout = '';
    let stderr = '';
    
    proc.stdout.on('data', (data) => { stdout += data; });
    proc.stderr.on('data', (data) => { stderr += data; });
    proc.on('close', (code) => { resolve({ stdout, stderr, code }); });
  });
}

// Main MCP Server
async function runMcpServer(): Promise<void> {
  const server = new Server(
    {
      name: 'context7-mcp',
      version: '1.0.0',
    },
    {
      capabilities: {
        tools: {},
      },
    }
  );

  // List available tools
  server.setRequestHandler(ListToolsRequestSchema, async () => {
    return {
      tools: [
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
      ],
    };
  });

  // Handle tool calls
  server.setRequestHandler(CallToolRequestSchema, async (request) => {
    const { name, arguments: args } = request.params;
    
    if (name === 'get-library-docs') {
      const libraryName = args?.libraryName as string;
      const query = args?.query as string | undefined;
      
      // Call upstream Context7 MCP via npx
      const result = await runNpx([
        '-y',
        '@upstash/context7-mcp@latest',
        'get-library-docs',
        libraryName,
        ...(query ? [query] : []),
      ]);
      
      if (result.code !== 0) {
        return {
          content: [{ type: 'text', text: `Error: ${result.stderr}` }],
          isError: true,
        };
      }
      
      return {
        content: [{ type: 'text', text: result.stdout }],
      };
    }
    
    if (name === 'search-docs') {
      const query = args?.query as string;
      const library = args?.library as string | undefined;
      
      const result = await runNpx([
        '-y',
        '@upstash/context7-mcp@latest',
        'search-docs',
        query,
        ...(library ? ['--library', library] : []),
      ]);
      
      if (result.code !== 0) {
        return {
          content: [{ type: 'text', text: `Error: ${result.stderr}` }],
          isError: true,
        };
      }
      
      return {
        content: [{ type: 'text', text: result.stdout }],
      };
    }
    
    return {
      content: [{ type: 'text', text: `Unknown tool: ${name}` }],
      isError: true,
    };
  });

  // Start server with stdio transport
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error('Context7 MCP server running on stdio');
}

// CLI entry point
async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const mode = args.includes('--mode') ? args[args.indexOf('--mode') + 1] : 'stdio';
  const apiKey = args.includes('--api-key') ? args[args.indexOf('--api-key') + 1] : undefined;
  
  switch (mode) {
    case 'local':
      await enableContext7('local');
      break;
      
    case 'remote':
      if (!apiKey) {
        console.error('Error: --api-key required for remote mode');
        process.exit(1);
      }
      await enableContext7('remote', apiKey);
      break;
      
    case 'disable':
      await disableContext7();
      break;
      
    case 'status':
      const status = await getStatus();
      console.log(`Context7 MCP: ${status.enabled ? 'enabled' : 'disabled'}`);
      if (status.enabled && status.mode) {
        console.log(`Mode: ${status.mode}`);
      }
      break;
      
    case 'stdio':
    default:
      await runMcpServer();
      break;
  }
}

main().catch((error) => {
  console.error('Fatal error:', error);
  process.exit(1);
});
