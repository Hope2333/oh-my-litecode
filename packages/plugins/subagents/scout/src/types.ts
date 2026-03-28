/**
 * Scout Subagent Types
 */

export type OutputFormat = 'json' | 'markdown' | 'text';

export interface ScoutConfig {
  outputFormat: OutputFormat;
  maxDepth: number;
  excludePatterns: string[];
}

export interface FileStats {
  totalFiles: number;
  totalLines: number;
  totalSize: number;
  byExtension: Record<string, number>;
  byDirectory: Record<string, number>;
}

export interface ComplexityMetrics {
  file: string;
  lines: number;
  functions: number;
  classes: number;
  complexity: number;
}

export interface DependencyNode {
  file: string;
  imports: string[];
  importedBy: string[];
}

export interface TreeOptions {
  maxDepth?: number;
  exclude?: string[];
  showFiles?: boolean;
  showDirs?: boolean;
}

export interface AnalyzeOptions {
  exclude?: string[];
  maxDepth?: number;
  format?: OutputFormat;
  output?: string;
}

export interface DepsOptions extends AnalyzeOptions {
  graph?: boolean;
}

export interface ReportOptions extends AnalyzeOptions {
  sections?: string[];
}

export interface ScoutResponse {
  success: boolean;
  content?: string | FileStats | ComplexityMetrics[] | DependencyNode[];
  error?: string;
  stats?: FileStats;
}
