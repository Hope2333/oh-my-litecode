/**
 * Debugger Subagent Types
 */

export type OutputFormat = 'json' | 'markdown' | 'text';

export interface DebuggerConfig {
  outputFormat: OutputFormat;
  maxDepth: number;
  excludePatterns: string[];
  debugLevel: 'basic' | 'standard' | 'deep';
}

export interface BugReport {
  file: string;
  line: number;
  type: 'syntax' | 'logic' | 'runtime' | 'type';
  severity: 'critical' | 'high' | 'medium' | 'low';
  description: string;
  suggestion: string;
  codeSnippet?: string;
}

export interface StackTrace {
  error: string;
  message: string;
  frames: StackFrame[];
}

export interface StackFrame {
  file: string;
  line: number;
  column: number;
  function?: string;
}

export interface FixSuggestion {
  bug: BugReport;
  fix: string;
  explanation: string;
  confidence: number;
}

export interface DebuggerResponse {
  success: boolean;
  content?: string | BugReport[] | StackTrace | FixSuggestion[];
  error?: string;
  bugs?: BugReport[];
}

export interface FindOptions {
  severity?: string[];
  types?: string[];
  format?: OutputFormat;
}

export interface AnalyzeOptions {
  format?: OutputFormat;
  includeSuggestions?: boolean;
}
