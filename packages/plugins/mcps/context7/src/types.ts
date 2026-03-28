/**
 * Context7 MCP Types
 */

export interface Context7Config {
  mode: 'local' | 'remote' | 'stdio';
  apiKey?: string;
  baseUrl?: string;
  localCommand?: string[];
}

export interface Context7Tool {
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

export interface Context7ToolCall {
  name: string;
  arguments?: Record<string, unknown>;
}

export interface Context7ToolResult {
  content: Array<{ type: string; text: string }>;
  isError?: boolean;
}

export interface Context7LibraryDocs {
  libraryName: string;
  query?: string;
  codeSnippets?: number;
  sourceReputation?: 'High' | 'Medium' | 'Low' | 'Unknown';
  benchmarkScore?: number;
  versions?: string[];
}

export interface Context7SearchResult {
  title: string;
  url: string;
  description: string;
  library?: string;
  relevanceScore?: number;
}

export interface Context7Response {
  success: boolean;
  data?: unknown;
  error?: string;
}
