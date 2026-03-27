import { describe, it, expect, beforeEach } from 'vitest';
import { Translator, setLocale, getLocale, t } from '../src/i18n/translator.js';

describe('Translator', () => {
  let translator: Translator;

  beforeEach(() => {
    translator = new Translator();
  });

  it('should initialize with default locale', () => {
    expect(translator.getLocale()).toBe('zh-CN');
  });

  it('should set locale', () => {
    translator.setLocale('en');
    expect(translator.getLocale()).toBe('en');
  });

  it('should throw for unsupported locale', () => {
    expect(() => translator.setLocale('fr' as any)).toThrow('Unsupported locale');
  });

  it('should translate simple key', () => {
    translator.setLocale('zh-CN');
    expect(translator.t('welcome')).toBe('欢迎');
  });

  it('should translate nested key', () => {
    translator.setLocale('zh-CN');
    expect(translator.t('session.create')).toBe('创建会话');
  });

  it('should fallback to en for missing translation', () => {
    translator.setLocale('ja');
    expect(translator.t('welcome')).toBe('ようこそ');
  });

  it('should return key for missing translation', () => {
    expect(translator.t('nonexistent.key')).toBe('nonexistent.key');
  });

  it('should interpolate params', () => {
    translator.addTranslations('en', { greeting: 'Hello, {{name}}!' });
    expect(translator.t('greeting', { name: 'World' })).toBe('Hello, World!');
  });

  it('should get supported locales', () => {
    const locales = translator.getSupportedLocales();
    expect(locales).toEqual(['en', 'zh-CN', 'zh-TW', 'ja', 'ko']);
  });

  it('should add translations', () => {
    translator.addTranslations('en', { custom: 'Custom translation' });
    expect(translator.t('custom')).toBe('Custom translation');
  });

  it('should get missing translations', () => {
    const missing = translator.getMissingTranslations('zh-CN');
    expect(missing).toBeDefined();
  });
});

describe('convenience functions', () => {
  it('should use default translator', () => {
    setLocale('en');
    expect(getLocale()).toBe('en');
    expect(t('welcome')).toBe('Welcome');
  });
});
