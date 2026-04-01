export type OutputFormat = 'json' | 'markdown' | 'text';
export interface DependencyCheckConfig { outputFormat: OutputFormat; }
export interface DependencyCheckResponse { success: boolean; content?: string; error?: string; }
