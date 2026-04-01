export type OutputFormat = 'json' | 'markdown' | 'text';
export interface LoggingSetupConfig { outputFormat: OutputFormat; }
export interface LoggingSetupResponse { success: boolean; content?: string; error?: string; }
