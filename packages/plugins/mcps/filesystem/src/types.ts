export interface FilesystemConfig {
  enabled: boolean;
}

export interface FilesystemResult {
  success: boolean;
  output?: string;
  error?: string;
}
