/**
 * Grep-App MCP Types
 */

export interface GrepAppConfig {
  defaultPath: string;
  maxResults: number;
  excludeDirs: string[];
  httpPort: number;
  mode: 'stdio' | 'http' | 'local';
}

export interface GrepSearchOptions {
  query: string;
  path?: string;
  extensions?: string[];
  excludeDirs?: string[];
  maxResults?: number;
  ignoreCase?: boolean;
  context?: number;
}

export interface GrepRegexOptions {
  pattern: string;
  path?: string;
  extensions?: string[];
  excludeDirs?: string[];
  maxResults?: number;
  ignoreCase?: boolean;
  context?: number;
}

export interface GrepCountOptions {
  pattern: string;
  path?: string;
  extensions?: string[];
  excludeDirs?: string[];
  ignoreCase?: boolean;
}

export interface GrepFilesOptions {
  pattern: string;
  path?: string;
  extensions?: string[];
  excludeDirs?: string[];
  maxResults?: number;
}

export interface GrepAdvancedOptions {
  pattern: string;
  path?: string;
  extensions?: string[];
  excludeDirs?: string[];
  maxResults?: number;
  ignoreCase?: boolean;
  context?: number;
  multiline?: boolean;
}

export interface GrepMatch {
  file: string;
  line: number;
  column: number;
  content: string;
}

export interface GrepResult {
  matches: GrepMatch[];
  totalMatches: number;
  totalFiles: number;
  searchPath: string;
  pattern: string;
}

export interface GrepCountResult {
  totalMatches: number;
  totalFiles: number;
  byFile: Array<{ file: string; count: number }>;
}

export interface GrepFileResult {
  files: string[];
  totalFiles: number;
}

export interface GrepTool {
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

export interface GrepToolCall {
  name: string;
  arguments?: Record<string, unknown>;
}

export interface GrepToolResult {
  content: Array<{ type: string; text: string }>;
  isError?: boolean;
}

export interface GrepResponse {
  success: boolean;
  data?: unknown;
  error?: string;
}
