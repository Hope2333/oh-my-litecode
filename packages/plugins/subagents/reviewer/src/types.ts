/**
 * Reviewer Subagent Types
 */

export type SeverityLevel = 'critical' | 'high' | 'medium' | 'low' | 'info';
export type OutputFormat = 'json' | 'markdown' | 'text';
export type CheckCategory = 'security' | 'style' | 'performance' | 'best-practices';

export interface ReviewerConfig {
  outputFormat: OutputFormat;
  maxIssues: number;
  excludePatterns: string[];
  securityEnabled: boolean;
  styleEnabled: boolean;
  performanceEnabled: boolean;
  bestPracticesEnabled: boolean;
  strictMode: boolean;
}

export interface ReviewIssue {
  id: string;
  severity: SeverityLevel;
  category: CheckCategory;
  file: string;
  line?: number;
  column?: number;
  message: string;
  suggestion?: string;
  code?: string;
}

export interface ReviewReport {
  directory: string;
  timestamp: string;
  totalIssues: number;
  issuesBySeverity: Record<SeverityLevel, number>;
  issuesByCategory: Record<CheckCategory, number>;
  issues: ReviewIssue[];
  score?: number;
}

export interface ReviewOptions {
  exclude?: string[];
  format?: OutputFormat;
  output?: string;
  strict?: boolean;
  noSecurity?: boolean;
  noStyle?: boolean;
  noPerformance?: boolean;
  noBestPractices?: boolean;
}

export interface SecurityOptions extends ReviewOptions {
  includeSensitive?: boolean;
  scoreOnly?: boolean;
}

export interface StyleOptions extends ReviewOptions {
  maxLineLength?: number;
  indentSize?: number;
  statsOnly?: boolean;
}

export interface ReviewerResponse {
  success: boolean;
  content?: string | ReviewReport | ReviewIssue[];
  error?: string;
  report?: ReviewReport;
}
