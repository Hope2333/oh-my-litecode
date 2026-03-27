/**
 * I18n Types - OML Modules
 */

export type Locale = 'en' | 'zh-CN' | 'zh-TW' | 'ja' | 'ko';

export interface Translation {
  [key: string]: string | Translation;
}

export interface I18nConfig {
  defaultLocale: Locale;
  fallbackLocale: Locale;
  supportedLocales: Locale[];
}

export interface I18nOptions {
  defaultLocale?: Locale;
  translations?: Partial<Record<Locale, Translation>>;
}
