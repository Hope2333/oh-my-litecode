/**
 * Librarian Subagent Types
 */

export interface LibrarianConfig {
  maxResults: number;
  outputFormat: OutputFormat;
  context7Enabled: boolean;
  webSearchEnabled: boolean;
  cacheEnabled: boolean;
  cacheTTL: number;
}

export type OutputFormat = 'json' | 'markdown' | 'text';

export type SearchSource = 'context7' | 'websearch' | 'all';

export type DedupMethod = 'url' | 'content' | 'hybrid';

export interface SearchResult {
  id: string;
  title: string;
  content: string;
  source: SearchSource;
  package?: string;
  url?: string;
  score?: number;
  text?: string;
  snippet?: string;
}

export interface SearchOptions {
  package?: string;
  limit?: number;
  format?: OutputFormat;
  sources?: SearchSource;
  dedup?: DedupMethod;
  output?: string;
}

export interface QueryOptions {
  limit?: number;
  format?: OutputFormat;
  registry?: string;
}

export interface WebSearchOptions {
  limit?: number;
  format?: OutputFormat;
  includeDomains?: string[];
  excludeDomains?: string[];
  withContent?: boolean;
}

export interface CompileOptions {
  searchQuery?: string;
  package?: string;
  web?: boolean;
  format?: OutputFormat;
  output?: string;
  includeCitations?: boolean;
  includeSummary?: boolean;
}

export interface CacheStats {
  files: number;
  size: string;
  directory: string;
}

export interface LibrarianResponse {
  success: boolean;
  content?: string | SearchResult[];
  error?: string;
  sources?: string[];
  cacheStats?: CacheStats;
}
