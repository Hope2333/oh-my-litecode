export type OutputFormat = 'json' | 'markdown' | 'text';
export interface ChaosTestingConfig { outputFormat: OutputFormat; }
export interface ChaosTestingResponse { success: boolean; content?: string; error?: string; }
