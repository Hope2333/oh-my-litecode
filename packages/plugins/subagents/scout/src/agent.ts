/**
 * Scout Subagent - Main Agent Class
 * Code analysis, dependency mapping, and repository statistics
 */

import type {
  ScoutConfig,
  ScoutResponse,
  FileStats,
  ComplexityMetrics,
  DependencyNode,
  TreeOptions,
  AnalyzeOptions,
  DepsOptions,
  ReportOptions,
  OutputFormat,
} from './types.js';

export class ScoutAgent {
  public readonly name = 'scout';
  public readonly version = '0.2.0';

  private config: ScoutConfig;
  private initialized: boolean;

  constructor() {
    this.initialized = false;
    this.config = {
      outputFormat: 'markdown',
      maxDepth: 10,
      excludePatterns: ['node_modules', '.git', '__pycache__', '.venv', 'dist', 'build', '.cache', 'target', 'coverage'],
    };
  }

  async initialize(config: Record<string, unknown>): Promise<void> {
    this.config = {
      ...this.config,
      outputFormat: (config.outputFormat as OutputFormat) || this.config.outputFormat,
      maxDepth: (config.maxDepth as number) || this.config.maxDepth,
      excludePatterns: (config.excludePatterns as string[]) || this.config.excludePatterns,
    };
    this.initialized = true;
    console.log(`[ScoutAgent] Initialized with maxDepth: ${this.config.maxDepth}`);
  }

  async shutdown(): Promise<void> {
    this.initialized = false;
    console.log('[ScoutAgent] Shutdown complete');
  }

  /**
   * Analyze codebase structure and complexity
   */
  async analyze(target: string, options: AnalyzeOptions = {}): Promise<ScoutResponse> {
    if (!this.initialized) {
      return { success: false, error: 'Agent not initialized' };
    }

    try {
      const stats = await this.analyzeDirectory(target, options);
      const complexity = await this.analyzeComplexity(target, options);
      
      const output = this.formatAnalysis(stats, complexity, options.format || this.config.outputFormat, target);
      return { success: true, content: output, stats };
    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Analysis failed',
      };
    }
  }

  /**
   * Generate file tree visualization
   */
  async tree(target: string, options: TreeOptions = {}): Promise<ScoutResponse> {
    if (!this.initialized) {
      return { success: false, error: 'Agent not initialized' };
    }

    try {
      const treeOutput = await this.generateTree(target, options);
      return { success: true, content: treeOutput };
    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Tree generation failed',
      };
    }
  }

  /**
   * Analyze dependencies and imports
   */
  async deps(target: string, options: DepsOptions = {}): Promise<ScoutResponse> {
    if (!this.initialized) {
      return { success: false, error: 'Agent not initialized' };
    }

    try {
      if (options.graph) {
        const graph = await this.buildDependencyGraph(target, options);
        return { success: true, content: this.formatDependencyGraph(graph) };
      } else {
        const deps = await this.analyzeDependencies(target, options);
        return { success: true, content: this.formatDependencies(deps, options.format || this.config.outputFormat) };
      }
    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Dependency analysis failed',
      };
    }
  }

  /**
   * Generate comprehensive analysis report
   */
  async report(target: string, options: ReportOptions = {}): Promise<ScoutResponse> {
    if (!this.initialized) {
      return { success: false, error: 'Agent not initialized' };
    }

    try {
      const report = await this.generateReport(target, options);
      return { success: true, content: report };
    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Report generation failed',
      };
    }
  }

  /**
   * Show file type statistics
   */
  async stats(target: string, options: AnalyzeOptions = {}): Promise<ScoutResponse> {
    if (!this.initialized) {
      return { success: false, error: 'Agent not initialized' };
    }

    try {
      const fileStats = await this.getFileStats(target, options);
      const output = this.formatStats(fileStats, options.format || this.config.outputFormat);
      return { success: true, content: output, stats: fileStats };
    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Stats generation failed',
      };
    }
  }

  // Private helper methods

  private async analyzeDirectory(target: string, _options: AnalyzeOptions = {}): Promise<FileStats> {
    // Simulated directory analysis
    return {
      totalFiles: 42,
      totalLines: 5280,
      totalSize: 125000,
      byExtension: {
        '.ts': 25,
        '.js': 10,
        '.json': 5,
        '.md': 2,
      },
      byDirectory: {
        src: 30,
        tests: 10,
        docs: 2,
      },
    };
  }

  private async analyzeComplexity(target: string, _options: AnalyzeOptions = {}): Promise<ComplexityMetrics[]> {
    // Simulated complexity analysis
    return [
      {
        file: `${target}/src/agent.ts`,
        lines: 250,
        functions: 15,
        classes: 1,
        complexity: 25,
      },
    ];
  }

  private async generateTree(target: string, options: TreeOptions = {}): Promise<string> {
    const maxDepth = options.maxDepth || 3;
    const showFiles = options.showFiles ?? true;
    
    let output = `${target}/\n`;
    output += `├── src/\n`;
    output += `│   ├── agent.ts\n`;
    output += `│   ├── types.ts\n`;
    output += `│   └── index.ts\n`;
    output += `├── tests/\n`;
    output += `│   └── agent.test.ts\n`;
    output += `├── package.json\n`;
    output += `└── README.md\n`;
    
    return output;
  }

  private async analyzeDependencies(target: string, _options: DepsOptions = {}): Promise<DependencyNode[]> {
    // Simulated dependency analysis
    return [
      {
        file: `${target}/src/agent.ts`,
        imports: ['./types.js'],
        importedBy: ['./index.ts'],
      },
    ];
  }

  private async buildDependencyGraph(target: string, _options: DepsOptions = {}): Promise<DependencyNode[]> {
    return this.analyzeDependencies(target);
  }

  private async getFileStats(target: string, _options: AnalyzeOptions = {}): Promise<FileStats> {
    return this.analyzeDirectory(target);
  }

  private async generateReport(target: string, options: ReportOptions = {}): Promise<string> {
    const stats = await this.analyzeDirectory(target, options);
    const complexity = await this.analyzeComplexity(target, options);
    const tree = await this.generateTree(target, { maxDepth: 3 });

    let output = '# Scout Analysis Report\n\n';
    output += `**Directory:** ${target}\n`;
    output += `**Generated:** ${new Date().toISOString()}\n\n`;
    output += '---\n\n';

    output += '## Overview\n\n';
    output += '```\n';
    output += `Total Files: ${stats.totalFiles}\n`;
    output += `Total Lines: ${stats.totalLines}\n`;
    output += `Total Size: ${(stats.totalSize / 1024).toFixed(2)} KB\n`;
    output += '```\n\n';

    output += '## File Structure\n\n';
    output += '```\n';
    output += tree;
    output += '```\n\n';

    output += '## Complexity Summary\n\n';
    output += '```json\n';
    output += JSON.stringify(complexity, null, 2);
    output += '\n```\n\n';

    return output;
  }

  private formatAnalysis(stats: FileStats, complexity: ComplexityMetrics[], format: OutputFormat, target: string): string {
    if (format === 'json') {
      return JSON.stringify({ stats, complexity }, null, 2);
    }

    let output = `# Codebase Analysis: ${target}\n\n`;
    output += `**Total Files:** ${stats.totalFiles}\n`;
    output += `**Total Lines:** ${stats.totalLines}\n`;
    output += `**Total Size:** ${(stats.totalSize / 1024).toFixed(2)} KB\n\n`;

    output += '## Files by Extension\n\n';
    for (const [ext, count] of Object.entries(stats.byExtension)) {
      output += `- ${ext}: ${count}\n`;
    }

    output += '\n## Complexity Metrics\n\n';
    for (const metric of complexity) {
      output += `- ${metric.file}: ${metric.complexity} complexity, ${metric.functions} functions\n`;
    }

    return output;
  }

  private formatDependencies(deps: DependencyNode[], format: OutputFormat): string {
    if (format === 'json') {
      return JSON.stringify(deps, null, 2);
    }

    let output = '# Dependencies\n\n';
    for (const dep of deps) {
      output += `## ${dep.file}\n\n`;
      output += `**Imports:** ${dep.imports.join(', ') || 'none'}\n`;
      output += `**Imported by:** ${dep.importedBy.join(', ') || 'none'}\n\n`;
    }

    return output;
  }

  private formatDependencyGraph(graph: DependencyNode[]): string {
    let output = 'digraph Dependencies {\n';
    for (const node of graph) {
      const nodeName = node.file.replace(/[^a-zA-Z0-9]/g, '_');
      for (const imp of node.imports) {
        const impName = imp.replace(/[^a-zA-Z0-9]/g, '_');
        output += `  ${nodeName} -> ${impName};\n`;
      }
    }
    output += '}\n';
    return output;
  }

  private formatStats(stats: FileStats, format: OutputFormat): string {
    if (format === 'json') {
      return JSON.stringify(stats, null, 2);
    }

    let output = 'File Statistics\n';
    output += '='.repeat(50) + '\n\n';
    output += `Total Files: ${stats.totalFiles}\n`;
    output += `Total Lines: ${stats.totalLines}\n`;
    output += `Total Size: ${(stats.totalSize / 1024).toFixed(2)} KB\n\n`;

    output += 'By Extension:\n';
    for (const [ext, count] of Object.entries(stats.byExtension)) {
      output += `  ${ext}: ${count}\n`;
    }

    output += '\nBy Directory:\n';
    for (const [dir, count] of Object.entries(stats.byDirectory)) {
      output += `  ${dir}: ${count}\n`;
    }

    return output;
  }

  getConfig(): ScoutConfig {
    return { ...this.config };
  }
}
