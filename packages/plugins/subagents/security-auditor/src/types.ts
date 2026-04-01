/**
 * Security Auditor Subagent Types
 */

export type OutputFormat = 'json' | 'markdown' | 'text';
export type Severity = 'critical' | 'high' | 'medium' | 'low';

export interface SecurityAuditorConfig {
  outputFormat: OutputFormat;
  severity: Severity;
}

export interface SecurityIssue {
  file: string;
  line: number;
  severity: Severity;
  type: 'injection' | 'xss' | 'csrf' | 'auth' | 'crypto';
  description: string;
  recommendation: string;
}

export interface SecurityAuditorResponse {
  success: boolean;
  content?: string;
  error?: string;
  issues?: SecurityIssue[];
}
