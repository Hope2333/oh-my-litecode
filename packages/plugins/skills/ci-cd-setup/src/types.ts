export type OutputFormat = 'json' | 'markdown' | 'text';
export interface CiCdSetupConfig { outputFormat: OutputFormat; }
export interface CiCdSetupResponse { success: boolean; content?: string; error?: string; }
