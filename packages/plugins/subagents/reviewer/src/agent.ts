/**
 * Reviewer Subagent - Main Agent Class
 * Code review, security auditing, style checking, and best practices validation
 */

import type {
  ReviewerConfig,
  ReviewerResponse,
  ReviewIssue,
  ReviewReport,
  ReviewOptions,
  SecurityOptions,
  StyleOptions,
  SeverityLevel,
  CheckCategory,
  OutputFormat,
} from './types.js';

export class ReviewerAgent {
  public readonly name = 'reviewer';
  public readonly version = '0.2.0';

  private config: ReviewerConfig;
  private initialized: boolean;

  constructor() {
    this.initialized = false;
    this.config = {
      outputFormat: 'markdown',
      maxIssues: 100,
      excludePatterns: ['node_modules', '.git', '__pycache__', '.venv', 'dist', 'build', '.cache', 'target', 'coverage', '.idea', '.vscode'],
      securityEnabled: true,
      styleEnabled: true,
      performanceEnabled: true,
      bestPracticesEnabled: true,
      strictMode: false,
    };
  }

  async initialize(config: Record<string, unknown>): Promise<void> {
    this.config = {
      ...this.config,
      outputFormat: (config.outputFormat as OutputFormat) || this.config.outputFormat,
      maxIssues: (config.maxIssues as number) || this.config.maxIssues,
      excludePatterns: (config.excludePatterns as string[]) || this.config.excludePatterns,
      securityEnabled: (config.securityEnabled as boolean) ?? this.config.securityEnabled,
      styleEnabled: (config.styleEnabled as boolean) ?? this.config.styleEnabled,
      performanceEnabled: (config.performanceEnabled as boolean) ?? this.config.performanceEnabled,
      bestPracticesEnabled: (config.bestPracticesEnabled as boolean) ?? this.config.bestPracticesEnabled,
      strictMode: (config.strictMode as boolean) ?? this.config.strictMode,
    };
    this.initialized = true;
    console.log(`[ReviewerAgent] Initialized with maxIssues: ${this.config.maxIssues}`);
  }

  async shutdown(): Promise<void> {
    this.initialized = false;
    console.log('[ReviewerAgent] Shutdown complete');
  }

  /**
   * Comprehensive code review (all checks)
   */
  async code(target: string, options: ReviewOptions = {}): Promise<ReviewerResponse> {
    if (!this.initialized) {
      return { success: false, error: 'Agent not initialized' };
    }

    try {
      const allIssues: ReviewIssue[] = [];

      // Run enabled checks
      if (this.config.securityEnabled && !options.noSecurity) {
        const securityIssues = await this.securityCheck(target, options);
        if (Array.isArray(securityIssues)) {
          allIssues.push(...securityIssues);
        }
      }

      if (this.config.styleEnabled && !options.noStyle) {
        const styleIssues = await this.styleCheck(target, options);
        if (Array.isArray(styleIssues)) {
          allIssues.push(...styleIssues);
        }
      }

      if (this.config.performanceEnabled && !options.noPerformance) {
        const perfIssues = await this.performanceCheck(target, options);
        if (Array.isArray(perfIssues)) {
          allIssues.push(...perfIssues);
        }
      }

      if (this.config.bestPracticesEnabled && !options.noBestPractices) {
        const bpIssues = await this.bestPracticesCheck(target, options);
        if (Array.isArray(bpIssues)) {
          allIssues.push(...bpIssues);
        }
      }

      // Limit issues
      const limitedIssues = allIssues.slice(0, this.config.maxIssues);

      // Format output
      const output = this.formatReport(limitedIssues, target, 'Code Review', options.format || this.config.outputFormat);

      // Check for critical issues in strict mode
      if (options.strict || this.config.strictMode) {
        const criticalCount = limitedIssues.filter((i) => i.severity === 'critical').length;
        if (criticalCount > 0) {
          return {
            success: false,
            error: `Found ${criticalCount} critical issues in strict mode`,
            content: output,
          };
        }
      }

      return { success: true, content: output };
    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Code review failed',
      };
    }
  }

  /**
   * Security vulnerability audit
   */
  async security(target: string, options: SecurityOptions = {}): Promise<ReviewerResponse> {
    if (!this.initialized) {
      return { success: false, error: 'Agent not initialized' };
    }

    try {
      const issues = await this.securityCheck(target, options);
      
      if (options.scoreOnly) {
        const score = this.calculateSecurityScore(issues);
        return { success: true, content: `Security Score: ${score}/100` };
      }

      const output = this.formatReport(issues, target, 'Security Audit', options.format || this.config.outputFormat);
      return { success: true, content: output };
    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Security audit failed',
      };
    }
  }

  /**
   * Code style and formatting check
   */
  async style(target: string, options: StyleOptions = {}): Promise<ReviewerResponse> {
    if (!this.initialized) {
      return { success: false, error: 'Agent not initialized' };
    }

    try {
      const issues = await this.styleCheck(target, options);

      if (options.statsOnly) {
        const stats = this.getStyleStats(issues);
        return { success: true, content: JSON.stringify(stats, null, 2) };
      }

      const output = this.formatReport(issues, target, 'Style Check', options.format || this.config.outputFormat);
      return { success: true, content: output };
    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Style check failed',
      };
    }
  }

  /**
   * Performance issue analysis
   */
  async performance(target: string, options: ReviewOptions = {}): Promise<ReviewerResponse> {
    if (!this.initialized) {
      return { success: false, error: 'Agent not initialized' };
    }

    try {
      const issues = await this.performanceCheck(target, options);

      if (options.format === 'text' || (options as SecurityOptions).scoreOnly) {
        const score = this.calculatePerformanceScore(issues);
        return { success: true, content: `Performance Score: ${score}/100` };
      }

      const output = this.formatReport(issues, target, 'Performance Analysis', options.format || this.config.outputFormat);
      return { success: true, content: output };
    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Performance analysis failed',
      };
    }
  }

  /**
   * Best practices compliance check
   */
  async bestPractices(target: string, options: ReviewOptions = {}): Promise<ReviewerResponse> {
    if (!this.initialized) {
      return { success: false, error: 'Agent not initialized' };
    }

    try {
      const issues = await this.bestPracticesCheck(target, options);

      if ((options as SecurityOptions).scoreOnly) {
        const score = this.calculateBestPracticesScore(issues);
        return { success: true, content: `Best Practices Score: ${score}/100` };
      }

      const output = this.formatReport(issues, target, 'Best Practices Check', options.format || this.config.outputFormat);
      return { success: true, content: output };
    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Best practices check failed',
      };
    }
  }

  /**
   * Generate structured review report
   */
  async report(target: string, options: ReviewOptions = {}): Promise<ReviewerResponse> {
    if (!this.initialized) {
      return { success: false, error: 'Agent not initialized' };
    }

    try {
      const report = await this.generateReport(target, options);
      const output = this.formatReportOutput(report, options.format || this.config.outputFormat);
      return { success: true, content: output, report };
    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Report generation failed',
      };
    }
  }

  // Private helper methods

  private async securityCheck(target: string, _options: ReviewOptions = {}): Promise<ReviewIssue[]> {
    // Simulated security check
    return [
      {
        id: `sec-${Date.now()}`,
        severity: 'high',
        category: 'security',
        file: `${target}/example.ts`,
        line: 10,
        message: 'Potential SQL injection vulnerability detected',
        suggestion: 'Use parameterized queries',
      },
    ];
  }

  private async styleCheck(target: string, _options: ReviewOptions = {}): Promise<ReviewIssue[]> {
    // Simulated style check
    return [
      {
        id: `style-${Date.now()}`,
        severity: 'low',
        category: 'style',
        file: `${target}/example.ts`,
        line: 5,
        message: 'Line exceeds maximum length (120 chars)',
        suggestion: 'Break line into multiple lines',
      },
    ];
  }

  private async performanceCheck(target: string, _options: ReviewOptions = {}): Promise<ReviewIssue[]> {
    // Simulated performance check
    return [
      {
        id: `perf-${Date.now()}`,
        severity: 'medium',
        category: 'performance',
        file: `${target}/example.ts`,
        line: 20,
        message: 'Inefficient loop detected',
        suggestion: 'Consider using Array.map() instead',
      },
    ];
  }

  private async bestPracticesCheck(target: string, _options: ReviewOptions = {}): Promise<ReviewIssue[]> {
    // Simulated best practices check
    return [
      {
        id: `bp-${Date.now()}`,
        severity: 'info',
        category: 'best-practices',
        file: `${target}/example.ts`,
        line: 1,
        message: 'Missing JSDoc comments',
        suggestion: 'Add documentation comments',
      },
    ];
  }

  private async generateReport(target: string, options: ReviewOptions = {}): Promise<ReviewReport> {
    const allIssues: ReviewIssue[] = [];

    if (this.config.securityEnabled && !options.noSecurity) {
      const issues = await this.securityCheck(target, options);
      allIssues.push(...issues);
    }

    if (this.config.styleEnabled && !options.noStyle) {
      const issues = await this.styleCheck(target, options);
      allIssues.push(...issues);
    }

    if (this.config.performanceEnabled && !options.noPerformance) {
      const issues = await this.performanceCheck(target, options);
      allIssues.push(...issues);
    }

    if (this.config.bestPracticesEnabled && !options.noBestPractices) {
      const issues = await this.bestPracticesCheck(target, options);
      allIssues.push(...issues);
    }

    const issuesBySeverity: Record<SeverityLevel, number> = {
      critical: 0,
      high: 0,
      medium: 0,
      low: 0,
      info: 0,
    };

    const issuesByCategory: Record<CheckCategory, number> = {
      security: 0,
      style: 0,
      performance: 0,
      'best-practices': 0,
    };

    allIssues.forEach((issue) => {
      issuesBySeverity[issue.severity]++;
      issuesByCategory[issue.category]++;
    });

    return {
      directory: target,
      timestamp: new Date().toISOString(),
      totalIssues: allIssues.length,
      issuesBySeverity,
      issuesByCategory,
      issues: allIssues.slice(0, this.config.maxIssues),
      score: this.calculateOverallScore(allIssues),
    };
  }

  private formatReport(issues: ReviewIssue[], target: string, title: string, format: OutputFormat): string {
    switch (format) {
      case 'json':
        return JSON.stringify(issues, null, 2);
      case 'markdown':
        return this.formatMarkdown(issues, target, title);
      case 'text':
      default:
        return this.formatText(issues, target, title);
    }
  }

  private formatMarkdown(issues: ReviewIssue[], target: string, title: string): string {
    let output = `# ${title} Report\n\n`;
    output += `**Directory:** ${target}\n`;
    output += `**Generated:** ${new Date().toISOString()}\n`;
    output += `**Total Issues:** ${issues.length}\n\n`;

    if (issues.length === 0) {
      output += '✅ No issues found!\n';
      return output;
    }

    const severities: SeverityLevel[] = ['critical', 'high', 'medium', 'low', 'info'];
    const emojis: Record<SeverityLevel, string> = {
      critical: '🔴',
      high: '🟠',
      medium: '🟡',
      low: '🔵',
      info: 'ℹ️',
    };

    for (const severity of severities) {
      const sevIssues = issues.filter((i) => i.severity === severity);
      if (sevIssues.length > 0) {
        output += `## ${emojis[severity]} ${severity.toUpperCase()} (${sevIssues.length})\n\n`;
        for (const issue of sevIssues) {
          output += `- **${issue.file}:${issue.line ?? '?'}**: ${issue.message}\n`;
          if (issue.suggestion) output += `  - *Suggestion:* ${issue.suggestion}\n`;
        }
        output += '\n';
      }
    }

    return output;
  }

  private formatText(issues: ReviewIssue[], target: string, title: string): string {
    let output = `${title} Report\n`;
    output += '='.repeat(50) + '\n';
    output += `Directory: ${target}\n`;
    output += `Generated: ${new Date().toISOString()}\n`;
    output += `Total Issues: ${issues.length}\n\n`;

    if (issues.length === 0) {
      output += 'No issues found!\n';
      return output;
    }

    for (const issue of issues) {
      output += `[${issue.severity.toUpperCase()}] ${issue.file}:${issue.line ?? '?'} - ${issue.message}\n`;
    }

    return output;
  }

  private formatReportOutput(report: ReviewReport, format: OutputFormat): string {
    if (format === 'json') {
      return JSON.stringify(report, null, 2);
    }
    return this.formatMarkdown(report.issues, report.directory, 'Comprehensive Review');
  }

  private calculateSecurityScore(issues: ReviewIssue[]): number {
    const weights: Record<SeverityLevel, number> = { critical: 25, high: 15, medium: 8, low: 3, info: 1 };
    let penalty = 0;
    issues.filter((i) => i.category === 'security').forEach((i) => (penalty += weights[i.severity]));
    return Math.max(0, 100 - penalty);
  }

  private calculatePerformanceScore(issues: ReviewIssue[]): number {
    const weights: Record<SeverityLevel, number> = { critical: 20, high: 12, medium: 6, low: 2, info: 1 };
    let penalty = 0;
    issues.filter((i) => i.category === 'performance').forEach((i) => (penalty += weights[i.severity]));
    return Math.max(0, 100 - penalty);
  }

  private calculateBestPracticesScore(issues: ReviewIssue[]): number {
    const weights: Record<SeverityLevel, number> = { critical: 15, high: 10, medium: 5, low: 2, info: 1 };
    let penalty = 0;
    issues.filter((i) => i.category === 'best-practices').forEach((i) => (penalty += weights[i.severity]));
    return Math.max(0, 100 - penalty);
  }

  private calculateOverallScore(issues: ReviewIssue[]): number {
    const weights: Record<SeverityLevel, number> = { critical: 20, high: 12, medium: 6, low: 2, info: 1 };
    let penalty = 0;
    issues.forEach((i) => (penalty += weights[i.severity]));
    return Math.max(0, 100 - penalty);
  }

  private getStyleStats(issues: ReviewIssue[]): Record<string, unknown> {
    return {
      totalIssues: issues.length,
      byType: issues.reduce((acc, i) => {
        acc[i.message] = (acc[i.message] || 0) + 1;
        return acc;
      }, {} as Record<string, number>),
    };
  }

  getConfig(): ReviewerConfig {
    return { ...this.config };
  }
}
