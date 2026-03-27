import { describe, expect, it } from 'vitest';
import { CacheManager } from '../src/cache/manager.js';
import { ErrorReporter } from '../src/error/reporter.js';
import { Translator, defaultTranslations } from '../src/i18n/translator.js';

describe('modules smoke', () => {
  it('stores and retrieves cache values', () => {
    const cache = new CacheManager<string>({ maxSize: 2, ttl: 1_000 });

    cache.set('key', 'value');

    expect(cache.get('key')).toBe('value');
    expect(cache.getStats().hits).toBe(1);
  });

  it('translates known keys and falls back to the key for missing entries', () => {
    const translator = new Translator({
      defaultLocale: 'zh-CN',
      fallbackLocale: 'en',
      translations: defaultTranslations,
    });

    expect(translator.t('welcome')).toBe('欢迎');
    expect(translator.t('missing.key')).toBe('missing.key');
  });

  it('collects error reports without requiring console output', () => {
    const reporter = new ErrorReporter({ reportToConsole: false });

    reporter.report(new Error('boom'), { lane: 'audit' }, 'high');

    expect(reporter.getReportCount()).toBe(1);
    expect(reporter.getReportsBySeverity('high')).toHaveLength(1);
  });
});
