/**
 * Optimizer Subagent Types
 */

export type OutputFormat = 'json' | 'markdown' | 'text';

export interface OptimizerConfig {
  outputFormat: OutputFormat;
  optimizationLevel: 'basic' | 'aggressive';
}

export interface OptimizationSuggestion {
  file: string;
  line: number;
  type: 'performance' | 'memory' | 'readability';
  description: string;
  suggestion: string;
  impact: 'low' | 'medium' | 'high';
}

export interface OptimizerResponse {
  success: boolean;
  content?: string;
  error?: string;
  suggestions?: OptimizationSuggestion[];
}
