export type OutputFormat = 'json' | 'markdown' | 'text';
export interface ErrorHandlingConfig { outputFormat: OutputFormat; }
export interface ErrorHandlingResponse { success: boolean; content?: string; error?: string; }
