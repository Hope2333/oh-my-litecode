export type OutputFormat = 'json' | 'markdown' | 'text';
export interface K8sSetupConfig { outputFormat: OutputFormat; }
export interface K8sSetupResponse { success: boolean; content?: string; error?: string; }
