/**
 * Architect Subagent Types
 */

export type OutputFormat = 'json' | 'markdown' | 'text';

export interface ArchitectConfig {
  outputFormat: OutputFormat;
  maxDepth: number;
  excludePatterns: string[];
  analysisLevel: 'basic' | 'standard' | 'deep';
}

export interface ArchitectureAnalysis {
  target: string;
  patterns: string[];
  components: ComponentInfo[];
  layers: LayerInfo[];
  dependencies: DependencyInfo[];
  issues: ArchitectureIssue[];
  recommendations: Recommendation[];
}

export interface ComponentInfo {
  name: string;
  type: string;
  path: string;
  responsibilities: string[];
  dependencies: string[];
  complexity: number;
}

export interface LayerInfo {
  name: string;
  components: string[];
  responsibilities: string[];
  violations: string[];
}

export interface DependencyInfo {
  from: string;
  to: string;
  type: 'import' | 'inheritance' | 'composition' | 'association';
  strength: 'strong' | 'weak';
}

export interface ArchitectureIssue {
  severity: 'critical' | 'high' | 'medium' | 'low';
  category: 'coupling' | 'cohesion' | 'layering' | 'circular' | 'complexity';
  description: string;
  location: string;
  suggestion: string;
}

export interface Recommendation {
  priority: 'high' | 'medium' | 'low';
  category: string;
  description: string;
  effort: 'low' | 'medium' | 'high';
  impact: 'low' | 'medium' | 'high';
}

export interface ArchitectResponse {
  success: boolean;
  content?: string | ArchitectureAnalysis;
  error?: string;
  analysis?: ArchitectureAnalysis;
}

export interface AnalyzeOptions {
  level?: 'basic' | 'standard' | 'deep';
  format?: OutputFormat;
  output?: string;
  includeTests?: boolean;
}

export interface ImproveOptions {
  focus?: string[];
  format?: OutputFormat;
}
