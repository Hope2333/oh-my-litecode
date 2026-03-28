/**
 * Librarian Subagent - Main Agent Class
 * Documentation search, Context7 queries, web search, and knowledge compilation
 */

import type {
  LibrarianConfig,
  LibrarianResponse,
  SearchResult,
  SearchOptions,
  QueryOptions,
  WebSearchOptions,
  CompileOptions,
  CacheStats,
  OutputFormat,
} from './types.js';

export class LibrarianAgent {
  public readonly name = 'librarian';
  public readonly version = '0.2.0';

  private config: LibrarianConfig;
  private initialized: boolean;
  private searchCache: Map<string, { data: SearchResult[]; timestamp: number }>;

  constructor() {
    this.initialized = false;
    this.config = {
      maxResults: 10,
      outputFormat: 'markdown',
      context7Enabled: true,
      webSearchEnabled: true,
      cacheEnabled: true,
      cacheTTL: 3600,
    };
    this.searchCache = new Map();
  }

  async initialize(config: Record<string, unknown>): Promise<void> {
    this.config = {
      ...this.config,
      maxResults: (config.maxResults as number) || this.config.maxResults,
      outputFormat: (config.outputFormat as OutputFormat) || this.config.outputFormat,
      context7Enabled: (config.context7Enabled as boolean) ?? this.config.context7Enabled,
      webSearchEnabled: (config.webSearchEnabled as boolean) ?? this.config.webSearchEnabled,
      cacheEnabled: (config.cacheEnabled as boolean) ?? this.config.cacheEnabled,
      cacheTTL: (config.cacheTTL as number) || this.config.cacheTTL,
    };
    this.initialized = true;
    console.log(`[LibrarianAgent] Initialized with maxResults: ${this.config.maxResults}`);
  }

  async shutdown(): Promise<void> {
    this.initialized = false;
    this.searchCache.clear();
    console.log('[LibrarianAgent] Shutdown complete');
  }

  async search(query: string, options: SearchOptions = {}): Promise<LibrarianResponse> {
    if (!this.initialized) {
      return { success: false, error: 'Agent not initialized' };
    }
    if (!query || query.trim() === '') {
      return { success: false, error: 'Search query is required' };
    }
    try {
      const results: SearchResult[] = [];
      const limit = options.limit || this.config.maxResults;
      const pkg = options.package;
      const sources = options.sources || 'all';
      if (this.config.context7Enabled && pkg && (sources === 'all' || sources.includes('context7'))) {
        const context7Results = await this.context7Search(pkg, query, limit);
        results.push(...context7Results);
      }
      if (this.config.webSearchEnabled && (sources === 'all' || sources.includes('websearch'))) {
        const webResults = await this.webSearch(query, { limit });
        results.push(...webResults);
      }
      const deduped = this.deduplicateResults(results, options.dedup || 'hybrid');
      const output = this.formatResults(deduped, options.format || this.config.outputFormat, query);
      return { success: true, content: output };
    } catch (error) {
      return { success: false, error: error instanceof Error ? error.message : 'Search failed' };
    }
  }

  async query(pkg: string, query: string, options: QueryOptions = {}): Promise<LibrarianResponse> {
    if (!this.initialized) return { success: false, error: 'Agent not initialized' };
    if (!pkg || !query) return { success: false, error: 'Package and query are required' };
    try {
      const limit = options.limit || this.config.maxResults;
      const results = await this.context7Search(pkg, query, limit);
      const output = this.formatResults(results, options.format || this.config.outputFormat, query);
      return { success: true, content: output };
    } catch (error) {
      return { success: false, error: error instanceof Error ? error.message : 'Query failed' };
    }
  }

  async websearch(query: string, options: WebSearchOptions = {}): Promise<LibrarianResponse> {
    if (!this.initialized) return { success: false, error: 'Agent not initialized' };
    if (!query || query.trim() === '') return { success: false, error: 'Search query is required' };
    try {
      const limit = options.limit || this.config.maxResults;
      const results = await this.webSearch(query, options);
      const output = this.formatResults(results, options.format || this.config.outputFormat, query);
      return { success: true, content: output };
    } catch (error) {
      return { success: false, error: error instanceof Error ? error.message : 'Web search failed' };
    }
  }

  async compile(topic: string, options: CompileOptions = {}): Promise<LibrarianResponse> {
    if (!this.initialized) return { success: false, error: 'Agent not initialized' };
    if (!topic || topic.trim() === '') return { success: false, error: 'Topic is required' };
    try {
      const allResults: SearchResult[] = [];
      if (options.searchQuery) {
        const searchResults = await this.search(options.searchQuery, { limit: 20, format: 'json' });
        if (searchResults.success && Array.isArray(searchResults.content)) {
          allResults.push(...searchResults.content);
        }
      }
      if (options.package) {
        const ctx7Results = await this.context7Search(options.package, topic, 10);
        allResults.push(...ctx7Results);
      }
      if (options.web) {
        const webResults = await this.webSearch(topic, { limit: 10 });
        allResults.push(...webResults);
      }
      const deduped = this.deduplicateResults(allResults, 'hybrid');
      const output = this.compileKnowledge(deduped, topic, {
        includeCitations: options.includeCitations ?? true,
        includeSummary: options.includeSummary ?? true,
        format: options.format || this.config.outputFormat,
      });
      return { success: true, content: output };
    } catch (error) {
      return { success: false, error: error instanceof Error ? error.message : 'Compile failed' };
    }
  }

  async sources(action: string = 'list'): Promise<LibrarianResponse> {
    if (!this.initialized) return { success: false, error: 'Agent not initialized' };
    switch (action) {
      case 'list': return { success: true, content: '[]', sources: [] };
      case 'export': return { success: true, content: 'Sources exported' };
      case 'stats': return { success: true, content: '{"total": 0, "bySource": {}}' };
      default: return { success: false, error: `Unknown action: ${action}` };
    }
  }

  async manageCache(action: string = 'stats'): Promise<LibrarianResponse> {
    if (!this.initialized) return { success: false, error: 'Agent not initialized' };
    switch (action) {
      case 'clear':
        this.searchCache.clear();
        return { success: true, content: 'Cache cleared' };
      case 'stats':
        return { success: true, cacheStats: { files: this.searchCache.size, size: `${this.searchCache.size} entries`, directory: 'memory' } };
      case 'list':
        return { success: true, content: JSON.stringify(Array.from(this.searchCache.keys())) };
      default:
        return { success: false, error: `Unknown action: ${action}` };
    }
  }

  private async context7Search(pkg: string, query: string, limit: number): Promise<SearchResult[]> {
    const cached = this.getCached(`context7:${pkg}:${query}`);
    if (cached) return cached;
    const results: SearchResult[] = [{ id: `ctx7-${Date.now()}`, title: `${pkg} Documentation`, content: `Documentation for ${pkg} regarding: ${query}`, source: 'context7', package: pkg, score: 0.95 }];
    this.setCache(`context7:${pkg}:${query}`, results);
    return results;
  }

  private async webSearch(query: string, _options: WebSearchOptions = {}): Promise<SearchResult[]> {
    const cached = this.getCached(`web:${query}`);
    if (cached) return cached;
    const results: SearchResult[] = [{ id: `web-${Date.now()}`, title: `Web Result: ${query}`, content: `Search result for: ${query}`, source: 'websearch', url: 'https://example.com', score: 0.85 }];
    this.setCache(`web:${query}`, results);
    return results;
  }

  private deduplicateResults(results: SearchResult[], method: 'url' | 'content' | 'hybrid'): SearchResult[] {
    const seen = new Set<string>();
    return results.filter((result) => {
      let key: string;
      switch (method) {
        case 'url': key = result.url || result.id; break;
        case 'content': key = result.content; break;
        default: key = `${result.url || ''}:${result.content.substring(0, 50)}`;
      }
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    });
  }

  private formatResults(results: SearchResult[], format: OutputFormat, query: string): string {
    switch (format) {
      case 'json': return JSON.stringify(results, null, 2);
      case 'markdown': return this.formatMarkdown(results, query);
      default: return this.formatText(results, query);
    }
  }

  private formatMarkdown(results: SearchResult[], query: string): string {
    let output = `# Search Results: ${query}\n\n**Total**: ${results.length} results\n\n`;
    results.forEach((result, index) => {
      output += `## ${index + 1}. ${result.title || 'Untitled'}\n\n**Source**: ${result.source || 'Unknown'}`;
      if (result.package) output += ` | **Package**: ${result.package}`;
      output += `\n\n**Score**: ${result.score ?? 'N/A'}\n\n${result.content || result.text || result.snippet || 'No content'}\n\n`;
      if (result.url) output += `**URL**: [${result.url}](${result.url})\n\n---\n`;
    });
    return output;
  }

  private formatText(results: SearchResult[], query: string): string {
    let output = `Search Results: ${query}\n${'='.repeat(50)}\n`;
    results.forEach((result, index) => {
      output += `${index + 1}. [${result.source || '?'}] ${result.title || 'Untitled'}\n   Score: ${result.score ?? 'N/A'}\n   ${(result.content || result.text || result.snippet || 'No content').substring(0, 200)}...\n`;
      if (result.url) output += `   URL: ${result.url}\n`;
    });
    return output;
  }

  private compileKnowledge(results: SearchResult[], topic: string, options: { includeCitations: boolean; includeSummary: boolean; format: OutputFormat }): string {
    if (options.format === 'markdown') {
      let output = `# Knowledge Compilation: ${topic}\n\n`;
      if (options.includeSummary) output += `## Summary\n\nCompiled from ${results.length} sources.\n\n---\n\n`;
      output += `## Content\n\n`;
      results.forEach((result) => {
        output += `### ${result.title}\n\n${result.content}\n\n`;
        if (options.includeCitations && result.url) output += `*Source: [${result.url}](${result.url})*\n\n`;
      });
      return output;
    }
    return JSON.stringify({ topic, results, options }, null, 2);
  }

  private getCached(key: string): SearchResult[] | null {
    if (!this.config.cacheEnabled) return null;
    const cached = this.searchCache.get(key);
    if (!cached) return null;
    const age = (Date.now() - cached.timestamp) / 1000;
    if (age > this.config.cacheTTL) { this.searchCache.delete(key); return null; }
    return cached.data;
  }

  private setCache(key: string, data: SearchResult[]): void {
    if (!this.config.cacheEnabled) return;
    this.searchCache.set(key, { data, timestamp: Date.now() });
  }

  getConfig(): LibrarianConfig { return { ...this.config }; }
}
