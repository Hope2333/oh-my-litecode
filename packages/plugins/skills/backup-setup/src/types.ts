export type OutputFormat = 'json' | 'markdown' | 'text';
export interface BackupSetupConfig { outputFormat: OutputFormat; schedule: string; retention: number; }
export interface BackupSetupResponse { success: boolean; content?: string; error?: string; }
