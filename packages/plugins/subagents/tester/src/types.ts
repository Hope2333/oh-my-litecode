/**
 * Tester Subagent Types
 */

export type OutputFormat = 'json' | 'markdown' | 'text';
export type TestFramework = 'jest' | 'vitest' | 'pytest' | 'bash';

export interface TesterConfig {
  outputFormat: OutputFormat;
  framework: TestFramework;
  coverageThreshold: number;
}

export interface TestCase {
  name: string;
  description: string;
  input: string;
  expectedOutput: string;
}

export interface CoverageReport {
  totalFiles: number;
  coveredLines: number;
  totalLines: number;
  percentage: number;
}

export interface TesterResponse {
  success: boolean;
  content?: string;
  error?: string;
  coverage?: CoverageReport;
}
