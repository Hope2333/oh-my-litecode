export type OutputFormat = 'json' | 'markdown' | 'text';
export interface MutationTestingConfig { outputFormat: OutputFormat; }
export interface MutationTestingResponse { success: boolean; content?: string; error?: string; }
