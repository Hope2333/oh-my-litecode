/**
 * I18n Translator - OML Modules
 * 
 * Internationalization with multi-language support.
 */

import type { Locale, Translation, I18nConfig, I18nOptions } from './types.js';

const DEFAULT_TRANSLATIONS: Record<Locale, Translation> = {
  'en': {
    welcome: 'Welcome',
    goodbye: 'Goodbye',
    error: 'An error occurred',
    success: 'Success',
    loading: 'Loading...',
    session: { create: 'Create session', delete: 'Delete session', list: 'List sessions' },
    backup: { start: 'Start backup', stop: 'Stop backup', restore: 'Restore backup' },
    conflict: { detect: 'Conflict detected', resolve: 'Resolve conflict' },
  },
  'zh-CN': {
    welcome: '欢迎',
    goodbye: '再见',
    error: '发生错误',
    success: '成功',
    loading: '加载中...',
    session: { create: '创建会话', delete: '删除会话', list: '列出会话' },
    backup: { start: '开始备份', stop: '停止备份', restore: '恢复备份' },
    conflict: { detect: '检测到冲突', resolve: '解决冲突' },
  },
  'zh-TW': {
    welcome: '歡迎',
    goodbye: '再見',
    error: '發生錯誤',
    success: '成功',
    loading: '加載中...',
    session: { create: '創建會話', delete: '刪除會話', list: '列出會話' },
    backup: { start: '開始備份', stop: '停止備份', restore: '恢復備份' },
    conflict: { detect: '檢測到衝突', resolve: '解決衝突' },
  },
  'ja': {
    welcome: 'ようこそ',
    goodbye: 'さようなら',
    error: 'エラーが発生しました',
    success: '成功',
    loading: '読み込み中...',
    session: { create: 'セッション作成', delete: 'セッション削除', list: 'セッション一覧' },
    backup: { start: 'バックアップ開始', stop: 'バックアップ停止', restore: 'バックアップ復元' },
    conflict: { detect: '競合検出', resolve: '競合解決' },
  },
  'ko': {
    welcome: '환영합니다',
    goodbye: '안녕히 가세요',
    error: '오류가 발생했습니다',
    success: '성공',
    loading: '로딩 중...',
    session: { create: '세션 생성', delete: '세션 삭제', list: '세션 목록' },
    backup: { start: '백업 시작', stop: '백업 중지', restore: '백업 복원' },
    conflict: { detect: '충돌 감지', resolve: '충돌 해결' },
  },
};

const CONFIG: I18nConfig = {
  defaultLocale: 'zh-CN',
  fallbackLocale: 'en',
  supportedLocales: ['en', 'zh-CN', 'zh-TW', 'ja', 'ko'],
};

export class Translator {
  private currentLocale: Locale;
  private translations: Record<Locale, Translation>;

  constructor(options?: I18nOptions) {
    this.currentLocale = options?.defaultLocale || CONFIG.defaultLocale;
    this.translations = { ...DEFAULT_TRANSLATIONS, ...options?.translations } as Record<Locale, Translation>;
  }

  /**
   * Set current locale
   */
  setLocale(locale: Locale): void {
    if (!CONFIG.supportedLocales.includes(locale)) {
      throw new Error(`Unsupported locale: ${locale}`);
    }
    this.currentLocale = locale;
  }

  /**
   * Get current locale
   */
  getLocale(): Locale {
    return this.currentLocale;
  }

  /**
   * Translate a key
   */
  t(key: string, params?: Record<string, string>): string {
    const translation = this.getTranslation(key, this.currentLocale) ||
                       this.getTranslation(key, CONFIG.fallbackLocale) ||
                       key;
    
    if (!params) return translation;
    
    return Object.entries(params).reduce((result, [key, value]) => {
      return result.replace(new RegExp(`\\{\\{${key}\\}\\}`, 'g'), value);
    }, translation);
  }

  /**
   * Get translation by key and locale
   */
  private getTranslation(key: string, locale: Locale): string | null {
    const translations = this.translations[locale];
    if (!translations) return null;
    
    const keys = key.split('.');
    let result: any = translations;
    
    for (const k of keys) {
      if (typeof result !== 'object' || !(k in result)) return null;
      result = result[k];
    }
    
    return typeof result === 'string' ? result : null;
  }

  /**
   * Get all supported locales
   */
  getSupportedLocales(): Locale[] {
    return [...CONFIG.supportedLocales];
  }

  /**
   * Add translations for a locale
   */
  addTranslations(locale: Locale, translations: Translation): void {
    this.translations[locale] = { ...this.translations[locale], ...translations };
  }

  /**
   * Get missing translations for a locale
   */
  getMissingTranslations(locale: Locale): string[] {
    const missing: string[] = [];
    const translations = this.translations[locale];
    
    const check = (obj: Translation, prefix: string = '') => {
      for (const [key, value] of Object.entries(obj)) {
        const fullKey = prefix ? `${prefix}.${key}` : key;
        if (typeof value === 'object') {
          check(value, fullKey);
        } else if (!translations || !(key in translations)) {
          missing.push(fullKey);
        }
      }
    };
    
    check(DEFAULT_TRANSLATIONS.en);
    return missing;
  }
}

// Default translator instance
let defaultTranslator: Translator | null = null;

export function getDefaultTranslator(): Translator {
  if (!defaultTranslator) {
    defaultTranslator = new Translator();
  }
  return defaultTranslator;
}

// Convenience functions
export const t = (key: string, params?: Record<string, string>) => getDefaultTranslator().t(key, params);
export const setLocale = (locale: Locale) => getDefaultTranslator().setLocale(locale);
export const getLocale = () => getDefaultTranslator().getLocale();
