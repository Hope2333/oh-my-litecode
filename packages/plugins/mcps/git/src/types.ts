export interface GitConfig {
  enabled: boolean;
}

export interface GitResult {
  success: boolean;
  output?: string;
  error?: string;
}
