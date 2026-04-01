/**
 * Translator Subagent Types
 */

export type OutputFormat = 'json' | 'markdown' | 'text';
export type Language = 'en' | 'zh' | 'ja' | 'es' | 'fr' | 'de';

export interface TranslatorConfig {
  outputFormat: OutputFormat;
  sourceLanguage: Language;
  targetLanguage: Language;
}

export interface TranslationResult {
  original: string;
  translated: string;
  sourceLanguage: Language;
  targetLanguage: Language;
  confidence: number;
}

export interface TranslatorResponse {
  success: boolean;
  content?: string;
  error?: string;
  translation?: TranslationResult;
}
