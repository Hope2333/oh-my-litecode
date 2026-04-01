export type OutputFormat = 'json' | 'markdown' | 'text';
export interface DockerSetupConfig { outputFormat: OutputFormat; }
export interface DockerSetupResponse { success: boolean; content?: string; error?: string; }
