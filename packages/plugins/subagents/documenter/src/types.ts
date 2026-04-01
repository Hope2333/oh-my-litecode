/**
 * Documenter Subagent Types
 */

export type OutputFormat = 'json' | 'markdown' | 'text';
export type DocType = 'api' | 'readme' | 'inline' | 'full';

export interface DocumenterConfig {
  outputFormat: OutputFormat;
  docType: DocType;
  excludePatterns: string[];
}

export interface DocumentSection {
  title: string;
  content: string;
  level: number;
}

export interface DocumenterResponse {
  success: boolean;
  content?: string;
  error?: string;
}

export interface GenerateOptions {
  docType?: DocType;
  format?: OutputFormat;
  output?: string;
}
