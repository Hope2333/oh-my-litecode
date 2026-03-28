/**
 * WebSearch MCP Types
 */

export interface WebSearchConfig {
  baseUrl: string;
  apiKey?: string;
  timeout: number;
  cacheEnabled: boolean;
  cacheTtl: number;
  cacheMaxSize: number;
}

export interface WebSearchOptions {
  query: string;
  numResults?: number;
  useAutoprompt?: boolean;
  type?: 'auto' | 'fast' | 'deep';
}

export interface CodeContextOptions {
  query: string;
  tokensNum?: number;
}

export interface WebSearchResult {
  title: string;
  url: string;
  description?: string;
  score?: number;
  publishedDate?: string;
}

export interface CodeContextResult {
  code: string;
  source: string;
  url: string;
  tokens: number;
}

export interface SearchResponse {
  results: WebSearchResult[];
  totalResults: number;
  query: string;
}

export interface CodeContextResponse {
  code: string;
  source: string;
  url: string;
  tokens: number;
}

export interface WebSearchTool {
  name: string;
  description: string;
  inputSchema: {
    type: 'object';
    properties: Record<string, {
      type: string;
      description: string;
    }>;
    required?: string[];
  };
}

export interface WebSearchToolCall {
  name: string;
  arguments?: Record<string, unknown>;
}

export interface WebSearchToolResult {
  content: Array<{ type: string; text: string }>;
  isError?: boolean;
}

export interface WebSearchResponse {
  success: boolean;
  data?: unknown;
  error?: string;
}

export interface CacheEntry {
  data: unknown;
  timestamp: number;
  hits: number;
}
