export interface NotificationConfig {
  enabled: boolean;
}

export interface NotificationResult {
  success: boolean;
  output?: string;
  error?: string;
}
