/**
 * Grep-App MCP Agent - Main Agent Class
 * 
 * Provides MCP service for local code search using grep
 */

import { exec } from 'child_process';
import { promisify } from 'util';
import { relative } from 'path';
import type {
  GrepAppConfig,
  GrepSearchOptions,
  GrepRegexOptions,
  GrepCountOptions,
  GrepFilesOptions,
  GrepAdvancedOptions,
  GrepMatch,
  GrepResult,
  GrepCountResult,
  GrepFileResult,
  GrepTool,
  GrepToolCall,
  GrepToolResult,
  GrepResponse,
} from './types.js';

const execAsync = promisify(exec);

const DEFAULT_CONFIG: GrepAppConfig = {
  defaultPath: '.',
  maxResults: 100,
  excludeDirs: ['node_modules', '.git', '__pycache__', '.venv', 'venv', 'dist', 'build'],
  httpPort: 8765,
  mode: 'stdio',
};

export class GrepAppAgent {
  public readonly name = 'grep-app';
  public readonly version = '0.2.0';
  
  private config: GrepAppConfig;
  private initialized: boolean;

  constructor() {
    this.initialized = false;
    this.config = { ...DEFAULT_CONFIG };
  }

  async initialize(config: Record<string, unknown>): Promise<void> {
    this.config = {
      ...this.config,
      defaultPath: (config.defaultPath as string) || process.env.GREP_APP_DEFAULT_PATH || '.',
      maxResults: (config.maxResults as number) || parseInt(process.env.GREP_APP_MAX_RESULTS || '100', 10),
      mode: (config.mode as 'stdio' | 'http' | 'local') || 'stdio',
    };
    
    if (config.excludeDirs) {
      this.config.excludeDirs = config.excludeDirs as string[];
    }
    
    this.initialized = true;
    console.log(`[GrepAppAgent] Initialized with default path: ${this.config.defaultPath}`);
  }

  async shutdown(): Promise<void> {
    this.initialized = false;
    console.log('[GrepAppAgent] Shutdown complete');
  }

  private buildGrepArgs(options: {
    pattern: string;
    path: string;
    extensions?: string[];
    excludeDirs?: string[];
    ignoreCase?: boolean;
    context?: number;
    maxResults?: number;
  }): string {
    const args = ['-n', '-H'];
    
    if (options.ignoreCase) {
      args.push('-i');
    }
    
    if (options.context) {
      args.push(`-C${options.context}`);
    }
    
    const excludeDirs = options.excludeDirs || this.config.excludeDirs;
    for (const dir of excludeDirs) {
      args.push(`--exclude-dir=${dir}`);
    }
    
    if (options.extensions && options.extensions.length > 0) {
      const extPattern = options.extensions.map(ext => `*.${ext}`).join(' ');
      args.push(`--include={${extPattern}}`);
    }
    
    const escapedPattern = options.pattern.replace(/'/g, "'\\''");
    args.push(`'${escapedPattern}'`);
    args.push(options.path);
    
    if (options.maxResults) {
      args.push(`| head -n ${options.maxResults}`);
    }
    
    return args.join(' ');
  }

  private parseGrepOutput(output: string, searchPath: string): GrepMatch[] {
    const matches: GrepMatch[] = [];
    const lines = output.trim().split('\n');
    
    for (const line of lines) {
      if (!line.trim()) continue;
      
      const match = line.match(/^([^:]+):(\d+):(.*)$/);
      if (match) {
        const [, file, lineNum, content] = match;
        matches.push({
          file: relative(searchPath, file) || file,
          line: parseInt(lineNum, 10),
          column: 0,
          content: content.trim(),
        });
      }
    }
    
    return matches;
  }

  async searchIntent(options: GrepSearchOptions): Promise<GrepResponse> {
    try {
      const pattern = this.queryToPattern(options.query);
      return await this.searchRegex({ ...options, pattern });
    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Search failed',
      };
    }
  }

  private queryToPattern(query: string): string {
    const patterns: string[] = [];
    
    if (query.includes('function') || query.includes('def')) {
      patterns.push('(function|def|fn)\\s+\\w+');
    }
    if (query.includes('class')) {
      patterns.push('class\\s+\\w+');
    }
    if (query.includes('todo') || query.includes('fixme')) {
      patterns.push('(TODO|FIXME|XXX|HACK)');
    }
    if (query.includes('import') || query.includes('require')) {
      patterns.push('(import|require)\\s*[\\(\\{]?');
    }
    
    if (patterns.length === 0) {
      return query.split('\\s+').join('.*');
    }
    
    return patterns.join('|');
  }

  async searchRegex(options: GrepRegexOptions): Promise<GrepResponse> {
    try {
      const path = options.path || this.config.defaultPath;
      const cmd = this.buildGrepArgs({
        pattern: options.pattern,
        path,
        extensions: options.extensions,
        excludeDirs: options.excludeDirs,
        ignoreCase: options.ignoreCase,
        context: options.context,
        maxResults: options.maxResults || this.config.maxResults,
      });

      const result = await execAsync(`grep -E ${cmd}`, {
        maxBuffer: 10 * 1024 * 1024,
      });

      const matches = this.parseGrepOutput(result.stdout || '', path);
      const uniqueFiles = new Set(matches.map(m => m.file));

      return {
        success: true,
        data: {
          matches,
          totalMatches: matches.length,
          totalFiles: uniqueFiles.size,
          searchPath: path,
          pattern: options.pattern,
        } as GrepResult,
      };
    } catch (error) {
      const err = error as { code?: number; stdout?: string; stderr?: string; message?: string };
      if (err.code === 1) {
        return {
          success: true,
          data: {
            matches: [],
            totalMatches: 0,
            totalFiles: 0,
            searchPath: options.path || this.config.defaultPath,
            pattern: options.pattern,
          } as GrepResult,
        };
      }
      return {
        success: false,
        error: err.stderr || err.message || 'Search failed',
      };
    }
  }

  async countMatches(options: GrepCountOptions): Promise<GrepResponse> {
    try {
      const path = options.path || this.config.defaultPath;
      const excludeDirs = options.excludeDirs || this.config.excludeDirs;
      
      let grepCmd = `grep -r -o`;
      if (options.ignoreCase) grepCmd += ' -i';
      
      for (const dir of excludeDirs) {
        grepCmd += ` --exclude-dir=${dir}`;
      }
      
      if (options.extensions && options.extensions.length > 0) {
        const extPattern = options.extensions.map(ext => `*.${ext}`).join(' ');
        grepCmd += ` --include={${extPattern}}`;
      }
      
      const escapedPattern = options.pattern.replace(/'/g, "'\\''");
      grepCmd += ` '${escapedPattern}' ${path} | wc -l`;

      const { stdout } = await execAsync(grepCmd);
      const totalMatches = parseInt(stdout.trim(), 10);

      let byFileCmd = `grep -r -l`;
      if (options.ignoreCase) byFileCmd += ' -i';
      
      for (const dir of excludeDirs) {
        byFileCmd += ` --exclude-dir=${dir}`;
      }
      
      byFileCmd += ` '${escapedPattern}' ${path}`;
      
      const { stdout: filesOutput } = await execAsync(byFileCmd);
      const files = filesOutput.trim().split('\n').filter(f => f.trim());
      
      return {
        success: true,
        data: {
          totalMatches,
          totalFiles: files.length,
          byFile: files.map(file => ({ file, count: 0 })),
        } as GrepCountResult,
      };
    } catch (error) {
      const err = error as { code?: number; message?: string };
      if (err.code === 1) {
        return {
          success: true,
          data: { totalMatches: 0, totalFiles: 0, byFile: [] } as GrepCountResult,
        };
      }
      return {
        success: false,
        error: err.message || 'Count failed',
      };
    }
  }

  async filesWithMatches(options: GrepFilesOptions): Promise<GrepResponse> {
    try {
      const path = options.path || this.config.defaultPath;
      const excludeDirs = options.excludeDirs || this.config.excludeDirs;
      
      let findCmd = `find ${path}`;
      
      for (const dir of excludeDirs) {
        findCmd += ` -name ${dir} -prune -o`;
      }
      
      findCmd += ` -type f`;
      
      if (options.extensions && options.extensions.length > 0) {
        findCmd += ` \\( ${options.extensions.map(ext => `-name *.${ext}`).join(' -o ')} \\)`;
      }
      
      findCmd += ` -exec grep -l '${options.pattern.replace(/'/g, "'\\''")}' {} \\;`;

      const { stdout } = await execAsync(findCmd, { maxBuffer: 10 * 1024 * 1024 });
      const files = stdout.trim().split('\n').filter(f => f.trim());
      
      const limitedFiles = options.maxResults 
        ? files.slice(0, options.maxResults) 
        : files;

      return {
        success: true,
        data: {
          files: limitedFiles.map(f => relative(path, f) || f),
          totalFiles: files.length,
        } as GrepFileResult,
      };
    } catch (error) {
      const err = error as { code?: number; message?: string };
      if (err.code === 1) {
        return {
          success: true,
          data: { files: [], totalFiles: 0 } as GrepFileResult,
        };
      }
      return {
        success: false,
        error: err.message || 'File search failed',
      };
    }
  }

  async advancedSearch(options: GrepAdvancedOptions): Promise<GrepResponse> {
    return this.searchRegex(options);
  }

  async callTool(toolCall: GrepToolCall): Promise<GrepToolResult> {
    const { name, arguments: args } = toolCall;
    
    try {
      let result: GrepResponse;
      
      switch (name) {
        case 'grep_search_intent':
          result = await this.searchIntent({
            query: args?.query as string,
            path: args?.path as string | undefined,
            extensions: args?.extensions as string[] | undefined,
          });
          break;
          
        case 'grep_regex':
          result = await this.searchRegex({
            pattern: args?.pattern as string,
            path: args?.path as string | undefined,
            extensions: args?.extensions as string[] | undefined,
          });
          break;
          
        case 'grep_count':
          result = await this.countMatches({
            pattern: args?.pattern as string,
            path: args?.path as string | undefined,
            extensions: args?.extensions as string[] | undefined,
          });
          break;
          
        case 'grep_files_with_matches':
          result = await this.filesWithMatches({
            pattern: args?.pattern as string,
            path: args?.path as string | undefined,
            extensions: args?.extensions as string[] | undefined,
          });
          break;
          
        case 'grep_advanced':
          result = await this.advancedSearch({
            pattern: args?.pattern as string,
            path: args?.path as string | undefined,
            extensions: args?.extensions as string[] | undefined,
            ignoreCase: args?.ignoreCase as boolean | undefined,
            context: args?.context as number | undefined,
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

  listTools(): GrepTool[] {
    return [
      {
        name: 'grep_search_intent',
        description: 'Natural language code search',
        inputSchema: {
          type: 'object',
          properties: {
            query: { type: 'string', description: 'Search query in natural language' },
            path: { type: 'string', description: 'Search path (default: current directory)' },
            extensions: { type: 'array', description: 'File extensions to search' },
          },
          required: ['query'],
        },
      },
      {
        name: 'grep_regex',
        description: 'Regular expression search',
        inputSchema: {
          type: 'object',
          properties: {
            pattern: { type: 'string', description: 'Regex pattern' },
            path: { type: 'string', description: 'Search path' },
            extensions: { type: 'array', description: 'File extensions' },
          },
          required: ['pattern'],
        },
      },
      {
        name: 'grep_count',
        description: 'Count pattern matches',
        inputSchema: {
          type: 'object',
          properties: {
            pattern: { type: 'string', description: 'Pattern to count' },
            path: { type: 'string', description: 'Search path' },
            extensions: { type: 'array', description: 'File extensions' },
          },
          required: ['pattern'],
        },
      },
      {
        name: 'grep_files_with_matches',
        description: 'List files with matches',
        inputSchema: {
          type: 'object',
          properties: {
            pattern: { type: 'string', description: 'Pattern to search' },
            path: { type: 'string', description: 'Search path' },
            extensions: { type: 'array', description: 'File extensions' },
          },
          required: ['pattern'],
        },
      },
      {
        name: 'grep_advanced',
        description: 'Advanced search with all options',
        inputSchema: {
          type: 'object',
          properties: {
            pattern: { type: 'string', description: 'Regex pattern' },
            path: { type: 'string', description: 'Search path' },
            extensions: { type: 'array', description: 'File extensions' },
            ignoreCase: { type: 'boolean', description: 'Case insensitive search' },
            context: { type: 'number', description: 'Context lines' },
          },
          required: ['pattern'],
        },
      },
    ];
  }

  getConfig(): GrepAppConfig { return { ...this.config }; }
  isInitialized(): boolean { return this.initialized; }
}
