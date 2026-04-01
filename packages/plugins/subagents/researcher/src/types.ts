/**
 * Researcher Subagent Types
 */

export type OutputFormat = 'json' | 'markdown' | 'text';

export interface ResearcherConfig {
  outputFormat: OutputFormat;
  maxResults: number;
}

export interface ResearchResult {
  title: string;
  source: string;
  url?: string;
  summary: string;
  relevance: number;
}

export interface ResearcherResponse {
  success: boolean;
  content?: string;
  error?: string;
  results?: ResearchResult[];
}
