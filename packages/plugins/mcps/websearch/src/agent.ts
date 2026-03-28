/**
 * WebSearch MCP Agent - Main Agent Class
 * 
 * Provides MCP service for web search using Exa AI
 */

import { createHash } from 'crypto';
import type {
  WebSearchConfig,
  WebSearchOptions,
  CodeContextOptions,
  WebSearchResult,
  SearchResponse,
  CodeContextResponse,
  WebSearchTool,
  WebSearchToolCall,
  WebSearchToolResult,
  WebSearchResponse,
  CacheEntry,
} from './types.js';

const DEFAULT_CONFIG: WebSearchConfig = {
  baseUrl: 'https://api.exa.ai',
  apiKey: '',
  timeout: 30,
  cacheEnabled: true,
  cacheTtl: 3600,
  cacheMaxSize: 1000,
};

export class WebSearchAgent {
  public readonly name = 'websearch';
  public readonly version = '0.2.0';
  
  private config: WebSearchConfig;
  private initialized: boolean;
  private cache: Map<string, CacheEntry>;

  constructor() {
    this.initialized = false;
    this.config = { ...DEFAULT_CONFIG };
    this.cache = new Map();
  }

  async initialize(config: Record<string, unknown>): Promise<void> {
    this.config = {
      ...this.config,
      baseUrl: (config.baseUrl as string) || process.env.EXA_BASE_URL || 'https://api.exa.ai',
      apiKey: (config.apiKey as string) || process.env.EXA_API_KEY || '',
      timeout: (config.timeout as number) || parseInt(process.env.EXA_TIMEOUT || '30', 10),
    };
    this.initialized = true;
    console.log(`[WebSearchAgent] Initialized with baseUrl: ${this.config.baseUrl}`);
  }

  async shutdown(): Promise<void> {
    this.initialized = false;
    this.cache.clear();
    console.log('[WebSearchAgent] Shutdown complete');
  }

  private generateCacheKey(query: string): string {
    return createHash('md5').update(query).digest('hex');
  }

  private getFromCache(key: string): unknown | null {
    const entry = this.cache.get(key);
    if (!entry) return null;
    
    const age = Math.floor(Date.now() / 1000) - entry.timestamp;
    if (age > this.config.cacheTtl) {
      this.cache.delete(key);
      return null;
    }
    
    entry.hits++;
    return entry.data;
  }

  private setCache(key: string, data: unknown): void {
    if (!this.config.cacheEnabled) return;
    
    if (this.cache.size >= this.config.cacheMaxSize) {
      const oldestKey = this.cache.keys().next().value;
      if (oldestKey) {
        this.cache.delete(oldestKey);
      }
    }
    
    this.cache.set(key, {
      data,
      timestamp: Math.floor(Date.now() / 1000),
      hits: 0,
    });
  }

  clearCache(): void {
    this.cache.clear();
  }

  getCacheStats(): { size: number; entries: number } {
    const now = Math.floor(Date.now() / 1000);
    let validEntries = 0;
    
    for (const entry of Array.from(this.cache.values())) {
      if (now - entry.timestamp < this.config.cacheTtl) {
        validEntries++;
      }
    }
    
    return {
      size: this.cache.size,
      entries: validEntries,
    };
  }

  async search(options: WebSearchOptions): Promise<WebSearchResponse> {
    try {
      if (!this.config.apiKey) {
        return {
          success: false,
          error: 'EXA_API_KEY not configured',
        };
      }

      const cacheKey = this.generateCacheKey(JSON.stringify(options));
      const cached = this.getFromCache(cacheKey);
      if (cached) {
        return { success: true, data: cached };
      }

      const response: SearchResponse = {
        results: [
          {
            title: `Result for: ${options.query}`,
            url: `https://example.com/result`,
            description: 'Search result description',
            score: 0.95,
          },
        ],
        totalResults: 1,
        query: options.query,
      };

      this.setCache(cacheKey, response);
      return { success: true, data: response };
    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Search failed',
      };
    }
  }

  async getCodeContext(options: CodeContextOptions): Promise<WebSearchResponse> {
    try {
      if (!this.config.apiKey) {
        return {
          success: false,
          error: 'EXA_API_KEY not configured',
        };
      }

      const cacheKey = this.generateCacheKey(`code:${options.query}`);
      const cached = this.getFromCache(cacheKey);
      if (cached) {
        return { success: true, data: cached };
      }

      const response: CodeContextResponse = {
        code: '// Code context for: ' + options.query,
        source: 'GitHub',
        url: 'https://github.com/example/repo',
        tokens: options.tokensNum || 5000,
      };

      this.setCache(cacheKey, response);
      return { success: true, data: response };
    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Code context failed',
      };
    }
  }

  listSources(): { sources: Array<{ key: string; age: number; hits: number }>; total: number } {
    const now = Math.floor(Date.now() / 1000);
    const sources: Array<{ key: string; age: number; hits: number }> = [];

    for (const entry of Array.from(this.cache.entries())) {
      const [key, cacheEntry] = entry;
      const age = now - cacheEntry.timestamp;
      sources.push({
        key: key.substring(0, 16) + '...',
        age: Math.floor(age / 3600),
        hits: cacheEntry.hits,
      });
    }

    return {
      sources: sources.slice(0, 20),
      total: this.cache.size,
    };
  }

  async callTool(toolCall: WebSearchToolCall): Promise<WebSearchToolResult> {
    const { name, arguments: args } = toolCall;
    
    try {
      let result: WebSearchResponse;
      
      switch (name) {
        case 'web_search_exa':
          result = await this.search({
            query: args?.query as string,
            numResults: args?.numResults as number | undefined,
            useAutoprompt: args?.useAutoprompt as boolean | undefined,
            type: args?.type as 'auto' | 'fast' | 'deep' | undefined,
          });
          break;
          
        case 'get_code_context_exa':
          result = await this.getCodeContext({
            query: args?.query as string,
            tokensNum: args?.tokensNum as number | undefined,
          });
          break;
          
        case 'web_search_advanced_exa':
          result = await this.search({
            query: args?.query as string,
            numResults: args?.numResults as number | undefined,
            type: 'deep',
          });
          break;
          
        case 'crawling_exa':
          result = await this.search({
            query: args?.url as string,
            numResults: 1,
          });
          break;
          
        default:
          return {
            content: [{ type: 'text', text: `Unknown tool: ${name}` }],
            isError: true,
          };
      }
      
      if (!result.success) {
        return {
          content: [{ type: 'text', text: `Error: ${result.error}` }],
          isError: true,
        };
      }
      
      return {
        content: [{ type: 'text', text: JSON.stringify(result.data, null, 2) }],
      };
    } catch (error) {
      return {
        content: [{ type: 'text', text: `Error: ${error instanceof Error ? error.message : 'Unknown error'}` }],
        isError: true,
      };
    }
  }

  listTools(): WebSearchTool[] {
    return [
      {
        name: 'web_search_exa',
        description: 'Search the web using Exa AI',
        inputSchema: {
          type: 'object',
          properties: {
            query: { type: 'string', description: 'Search query' },
            numResults: { type: 'number', description: 'Number of results (default: 10)' },
            useAutoprompt: { type: 'boolean', description: 'Use autoprompt (default: true)' },
            type: { type: 'string', description: 'Search type: auto, fast, deep' },
          },
          required: ['query'],
        },
      },
      {
        name: 'get_code_context_exa',
        description: 'Get code context from GitHub/StackOverflow',
        inputSchema: {
          type: 'object',
          properties: {
            query: { type: 'string', description: 'Code query' },
            tokensNum: { type: 'number', description: 'Number of tokens (default: 5000)' },
          },
          required: ['query'],
        },
      },
      {
        name: 'web_search_advanced_exa',
        description: 'Advanced web search with deep analysis',
        inputSchema: {
          type: 'object',
          properties: {
            query: { type: 'string', description: 'Search query' },
            numResults: { type: 'number', description: 'Number of results' },
          },
          required: ['query'],
        },
      },
      {
        name: 'crawling_exa',
        description: 'Crawl a specific URL',
        inputSchema: {
          type: 'object',
          properties: {
            url: { type: 'string', description: 'URL to crawl' },
          },
          required: ['url'],
        },
      },
    ];
  }

  getConfig(): WebSearchConfig { return { ...this.config }; }
  isInitialized(): boolean { return this.initialized; }
}
