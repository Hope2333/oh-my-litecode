export type OutputFormat = 'json' | 'markdown' | 'text';
export interface PerformanceTuningConfig { outputFormat: OutputFormat; }
export interface PerformanceTuningResponse { success: boolean; content?: string; error?: string; }
