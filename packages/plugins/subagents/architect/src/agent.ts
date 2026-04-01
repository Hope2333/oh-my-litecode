/**
 * Architect Subagent - Main Agent Class
 * Architecture analysis, improvement suggestions, and design pattern recommendations
 */

import type {
  ArchitectConfig,
  ArchitectResponse,
  ArchitectureAnalysis,
  ComponentInfo,
  LayerInfo,
  DependencyInfo,
  ArchitectureIssue,
  Recommendation,
  AnalyzeOptions,
  ImproveOptions,
  OutputFormat,
} from './types.js';

export class ArchitectAgent {
  public readonly name = 'architect';
  public readonly version = '0.2.0';

  private config: ArchitectConfig;
  private initialized: boolean;

  constructor() {
    this.initialized = false;
    this.config = {
      outputFormat: 'markdown',
      maxDepth: 10,
      excludePatterns: ['node_modules', '.git', '__pycache__', '.venv', 'dist', 'build', '.cache', 'target', 'coverage'],
      analysisLevel: 'standard',
    };
  }

  async initialize(config: Record<string, unknown>): Promise<void> {
    this.config = {
      ...this.config,
      outputFormat: (config.outputFormat as OutputFormat) || this.config.outputFormat,
      analysisLevel: (config.analysisLevel as 'basic' | 'standard' | 'deep') || this.config.analysisLevel,
      maxDepth: (config.maxDepth as number) || this.config.maxDepth,
      excludePatterns: (config.excludePatterns as string[]) || this.config.excludePatterns,
    };
    this.initialized = true;
    console.log(`[ArchitectAgent] Initialized with analysisLevel: ${this.config.analysisLevel}`);
  }

  async shutdown(): Promise<void> {
    this.initialized = false;
    console.log('[ArchitectAgent] Shutdown complete');
  }

  /**
   * Analyze codebase architecture
   */
  async analyzeArchitecture(target: string, options: AnalyzeOptions = {}): Promise<ArchitectResponse> {
    if (!this.initialized) {
      return { success: false, error: 'Agent not initialized' };
    }

    try {
      const analysis = await this.performAnalysis(target, options);
      const output = this.formatAnalysis(analysis, options.format || this.config.outputFormat);
      return { success: true, content: output, analysis };
    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Architecture analysis failed',
      };
    }
  }

  /**
   * Suggest architecture improvements
   */
  async suggestImprovements(target: string, options: ImproveOptions = {}): Promise<ArchitectResponse> {
    if (!this.initialized) {
      return { success: false, error: 'Agent not initialized' };
    }

    try {
      const analysis = await this.performAnalysis(target, {});
      const improvements = this.generateImprovements(analysis, options.focus);
      const output = this.formatImprovements(improvements, options.format || this.config.outputFormat);
      return { success: true, content: output };
    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Improvement suggestions failed',
      };
    }
  }

  /**
   * Check design patterns usage
   */
  async checkPatterns(target: string): Promise<ArchitectResponse> {
    if (!this.initialized) {
      return { success: false, error: 'Agent not initialized' };
    }

    try {
      const patterns = await this.detectPatterns(target);
      const output = this.formatPatterns(patterns);
      return { success: true, content: output };
    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Pattern detection failed',
      };
    }
  }

  /**
   * Generate architecture documentation
   */
  async generateDocs(target: string): Promise<ArchitectResponse> {
    if (!this.initialized) {
      return { success: false, error: 'Agent not initialized' };
    }

    try {
      const analysis = await this.performAnalysis(target, {});
      const docs = this.generateDocumentation(analysis);
      return { success: true, content: docs };
    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Documentation generation failed',
      };
    }
  }

  // Private helper methods

  private async performAnalysis(target: string, options: AnalyzeOptions = {}): Promise<ArchitectureAnalysis> {
    const level = options.level || this.config.analysisLevel;
    
    // Simulated architecture analysis
    return {
      target,
      patterns: ['MVC', 'Repository', 'Service Layer'],
      components: [
        {
          name: 'Controller',
          type: 'layer',
          path: `${target}/src/controllers`,
          responsibilities: ['Handle HTTP requests', 'Route to services'],
          dependencies: ['Service', 'DTO'],
          complexity: 15,
        },
        {
          name: 'Service',
          type: 'layer',
          path: `${target}/src/services`,
          responsibilities: ['Business logic', 'Transaction management'],
          dependencies: ['Repository', 'Model'],
          complexity: 25,
        },
        {
          name: 'Repository',
          type: 'pattern',
          path: `${target}/src/repositories`,
          responsibilities: ['Data access', 'Query building'],
          dependencies: ['Model', 'Database'],
          complexity: 10,
        },
      ],
      layers: [
        {
          name: 'Presentation',
          components: ['Controller', 'Middleware', 'Validator'],
          responsibilities: ['Handle user input', 'Format output'],
          violations: [],
        },
        {
          name: 'Business',
          components: ['Service', 'Domain Model'],
          responsibilities: ['Core business logic'],
          violations: [],
        },
        {
          name: 'Data',
          components: ['Repository', 'Entity'],
          responsibilities: ['Data persistence'],
          violations: [],
        },
      ],
      dependencies: [
        { from: 'Controller', to: 'Service', type: 'composition', strength: 'strong' },
        { from: 'Service', to: 'Repository', type: 'composition', strength: 'strong' },
        { from: 'Repository', to: 'Entity', type: 'association', strength: 'weak' },
      ],
      issues: [
        {
          severity: 'medium',
          category: 'coupling',
          description: 'High coupling between Controller and Service layers',
          location: `${target}/src/controllers`,
          suggestion: 'Consider using dependency injection',
        },
      ],
      recommendations: [
        {
          priority: 'high',
          category: 'Architecture',
          description: 'Implement dependency injection for better testability',
          effort: 'medium',
          impact: 'high',
        },
        {
          priority: 'medium',
          category: 'Performance',
          description: 'Add caching layer for frequently accessed data',
          effort: 'medium',
          impact: 'medium',
        },
      ],
    };
  }

  private async detectPatterns(target: string): Promise<string[]> {
    return ['Singleton', 'Factory', 'Observer', 'Repository', 'Service Layer'];
  }

  private generateImprovements(analysis: ArchitectureAnalysis, focus?: string[]): Recommendation[] {
    const recommendations: Recommendation[] = [];
    
    // Add existing recommendations
    recommendations.push(...analysis.recommendations);
    
    // Add focus-specific recommendations
    if (focus?.includes('performance')) {
      recommendations.push({
        priority: 'high',
        category: 'Performance',
        description: 'Implement lazy loading for heavy components',
        effort: 'medium',
        impact: 'high',
      });
    }
    
    if (focus?.includes('maintainability')) {
      recommendations.push({
        priority: 'medium',
        category: 'Maintainability',
        description: 'Split large services into smaller domain services',
        effort: 'high',
        impact: 'medium',
      });
    }
    
    return recommendations;
  }

  private generateDocumentation(analysis: ArchitectureAnalysis): string {
    let docs = '# Architecture Documentation\n\n';
    docs += `**Target:** ${analysis.target}\n`;
    docs += `**Generated:** ${new Date().toISOString()}\n\n`;
    docs += '---\n\n';

    docs += '## Overview\n\n';
    docs += `This codebase follows the **${analysis.patterns.join(', ')}** architectural patterns.\n\n`;

    docs += '## Components\n\n';
    for (const component of analysis.components) {
      docs += `### ${component.name}\n\n`;
      docs += `- **Type:** ${component.type}\n`;
      docs += `- **Path:** ${component.path}\n`;
      docs += `- **Complexity:** ${component.complexity}\n`;
      docs += `- **Responsibilities:** ${component.responsibilities.join(', ')}\n`;
      docs += `- **Dependencies:** ${component.dependencies.join(', ')}\n\n`;
    }

    docs += '## Layers\n\n';
    for (const layer of analysis.layers) {
      docs += `### ${layer.name} Layer\n\n`;
      docs += `- **Components:** ${layer.components.join(', ')}\n`;
      docs += `- **Responsibilities:** ${layer.responsibilities.join(', ')}\n\n`;
    }

    docs += '## Issues\n\n';
    if (analysis.issues.length === 0) {
      docs += 'No significant architecture issues found.\n\n';
    } else {
      for (const issue of analysis.issues) {
        docs += `### [${issue.severity.toUpperCase()}] ${issue.category}\n\n`;
        docs += `- **Description:** ${issue.description}\n`;
        docs += `- **Location:** ${issue.location}\n`;
        docs += `- **Suggestion:** ${issue.suggestion}\n\n`;
      }
    }

    return docs;
  }

  private formatAnalysis(analysis: ArchitectureAnalysis, format: OutputFormat): string {
    if (format === 'json') {
      return JSON.stringify(analysis, null, 2);
    }

    let output = `# Architecture Analysis: ${analysis.target}\n\n`;
    output += `**Patterns:** ${analysis.patterns.join(', ')}\n\n`;

    output += '## Components\n\n';
    for (const comp of analysis.components) {
      output += `- **${comp.name}** (${comp.type}): complexity ${comp.complexity}\n`;
    }

    output += '\n## Issues\n\n';
    for (const issue of analysis.issues) {
      output += `- [${issue.severity}] ${issue.description}\n`;
    }

    output += '\n## Recommendations\n\n';
    for (const rec of analysis.recommendations) {
      output += `- [${rec.priority}] ${rec.description}\n`;
    }

    return output;
  }

  private formatImprovements(improvements: Recommendation[], format: OutputFormat): string {
    if (format === 'json') {
      return JSON.stringify(improvements, null, 2);
    }

    let output = '# Architecture Improvement Suggestions\n\n';
    for (const imp of improvements) {
      output += `## [${imp.priority.toUpperCase()}] ${imp.category}\n\n`;
      output += `${imp.description}\n\n`;
      output += `- Effort: ${imp.effort}\n`;
      output += `- Impact: ${imp.impact}\n\n`;
    }

    return output;
  }

  private formatPatterns(patterns: string[]): string {
    let output = '# Design Patterns Detected\n\n';
    for (const pattern of patterns) {
      output += `- ${pattern}\n`;
    }
    return output;
  }

  getConfig(): ArchitectConfig {
    return { ...this.config };
  }
}
