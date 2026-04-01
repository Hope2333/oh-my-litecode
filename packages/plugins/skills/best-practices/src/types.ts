export type OutputFormat = 'json' | 'markdown' | 'text';
export interface BestPracticesConfig { outputFormat: OutputFormat; }
export interface BestPracticesResponse { success: boolean; content?: string; error?: string; }
