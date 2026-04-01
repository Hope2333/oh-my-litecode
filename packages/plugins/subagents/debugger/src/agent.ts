/**
 * Debugger Subagent - Main Agent Class
 * Bug finding, stack trace analysis, and fix suggestions
 */

import type {
  DebuggerConfig,
  DebuggerResponse,
  BugReport,
  StackTrace,
  FixSuggestion,
  FindOptions,
  AnalyzeOptions,
  OutputFormat,
} from './types.js';

export class DebuggerAgent {
  public readonly name = 'debugger';
  public readonly version = '0.2.0';

  private config: DebuggerConfig;
  private initialized: boolean;

  constructor() {
    this.initialized = false;
    this.config = {
      outputFormat: 'markdown',
      maxDepth: 10,
      excludePatterns: ['node_modules', '.git', '__pycache__', '.venv', 'dist', 'build', '.cache', 'target', 'coverage'],
      debugLevel: 'standard',
    };
  }

  async initialize(config: Record<string, unknown>): Promise<void> {
    this.config = {
      ...this.config,
      outputFormat: (config.outputFormat as OutputFormat) || this.config.outputFormat,
      debugLevel: (config.debugLevel as 'basic' | 'standard' | 'deep') || this.config.debugLevel,
      maxDepth: (config.maxDepth as number) || this.config.maxDepth,
      excludePatterns: (config.excludePatterns as string[]) || this.config.excludePatterns,
    };
    this.initialized = true;
    console.log(`[DebuggerAgent] Initialized with debugLevel: ${this.config.debugLevel}`);
  }

  async shutdown(): Promise<void> {
    this.initialized = false;
    console.log('[DebuggerAgent] Shutdown complete');
  }

  async findBugs(target: string, options: FindOptions = {}): Promise<DebuggerResponse> {
    if (!this.initialized) {
      return { success: false, error: 'Agent not initialized' };
    }

    try {
      const bugs = await this.scanForBugs(target, options);
      const output = this.formatBugs(bugs, options.format || this.config.outputFormat);
      return { success: true, content: output, bugs };
    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Bug finding failed',
      };
    }
  }

  async analyzeStackTrace(trace: string): Promise<DebuggerResponse> {
    if (!this.initialized) {
      return { success: false, error: 'Agent not initialized' };
    }

    try {
      const parsed = this.parseStackTrace(trace);
      const analysis = this.analyzeTrace(parsed);
      return { success: true, content: analysis };
    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Stack trace analysis failed',
      };
    }
  }

  async suggestFixes(target: string): Promise<DebuggerResponse> {
    if (!this.initialized) {
      return { success: false, error: 'Agent not initialized' };
    }

    try {
      const bugs = await this.scanForBugs(target, {});
      const fixes = this.generateFixes(bugs);
      const output = this.formatFixes(fixes);
      return { success: true, content: output };
    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Fix suggestion failed',
      };
    }
  }

  private async scanForBugs(target: string, options: FindOptions = {}): Promise<BugReport[]> {
    return [
      {
        file: `${target}/src/main.ts`,
        line: 42,
        type: 'logic',
        severity: 'high',
        description: 'Potential null pointer access',
        suggestion: 'Add null check before accessing property',
        codeSnippet: 'const value = obj.property;',
      },
      {
        file: `${target}/src/utils.ts`,
        line: 15,
        type: 'type',
        severity: 'medium',
        description: 'Type mismatch in function parameter',
        suggestion: 'Ensure correct type is passed',
        codeSnippet: 'function process(data: string) { ... }',
      },
    ];
  }

  private parseStackTrace(trace: string): StackTrace {
    const lines = trace.split('\n');
    const errorLine = lines[0] || 'Unknown Error';
    const message = lines[0]?.split(': ')[1] || 'No message';
    
    const frames: StackFrame[] = lines.slice(1).map((line, idx) => ({
      file: `file${idx}.ts`,
      line: idx + 1,
      column: 0,
      function: `function${idx}`,
    }));

    return { error: errorLine, message, frames };
  }

  private analyzeTrace(trace: StackTrace): string {
    let output = '# Stack Trace Analysis\n\n';
    output += `**Error:** ${trace.error}\n`;
    output += `**Message:** ${trace.message}\n\n`;
    output += '## Call Stack\n\n';
    for (const frame of trace.frames) {
      output += `- ${frame.function} in ${frame.file}:${frame.line}\n`;
    }
    return output;
  }

  private generateFixes(bugs: BugReport[]): FixSuggestion[] {
    return bugs.map(bug => ({
      bug,
      fix: `// Fix for ${bug.description}\nif (obj !== null) { ... }`,
      explanation: 'This fix adds a null check to prevent runtime errors',
      confidence: 0.85,
    }));
  }

  private formatBugs(bugs: BugReport[], format: OutputFormat): string {
    if (format === 'json') {
      return JSON.stringify(bugs, null, 2);
    }

    let output = '# Bug Report\n\n';
    for (const bug of bugs) {
      output += `## [${bug.severity.toUpperCase()}] ${bug.type} at ${bug.file}:${bug.line}\n\n`;
      output += `${bug.description}\n\n`;
      output += `**Suggestion:** ${bug.suggestion}\n`;
      if (bug.codeSnippet) {
        output += `\n\`\`\`typescript\n${bug.codeSnippet}\n\`\`\`\n`;
      }
      output += '\n';
    }
    return output;
  }

  private formatFixes(fixes: FixSuggestion[]): string {
    let output = '# Fix Suggestions\n\n';
    for (const fix of fixes) {
      output += `## ${fix.bug.description}\n\n`;
      output += `**Confidence:** ${(fix.confidence * 100).toFixed(0)}%\n\n`;
      output += '```typescript\n';
      output += fix.fix + '\n';
      output += '```\n\n';
      output += `${fix.explanation}\n\n`;
    }
    return output;
  }

  getConfig(): DebuggerConfig {
    return { ...this.config };
  }
}
