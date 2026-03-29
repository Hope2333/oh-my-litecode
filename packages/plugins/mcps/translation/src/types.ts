export interface TranslationConfig {
  enabled: boolean;
}

export interface TranslationResult {
  success: boolean;
  output?: string;
  error?: string;
}
