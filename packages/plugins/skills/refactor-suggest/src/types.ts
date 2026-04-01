export type OutputFormat = 'json' | 'markdown' | 'text';
export interface RefactorSuggestConfig { outputFormat: OutputFormat; }
export interface RefactorSuggestResponse { success: boolean; content?: string; error?: string; }
