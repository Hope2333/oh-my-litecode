import { describe, it, expect, vi, beforeEach } from 'vitest';
import { parseVersion, VersionSync } from '../src/version-sync.js';

describe('parseVersion', () => {
  it('parses simple version v1.5.10', () => {
    const result = parseVersion('v1.5.10');
    expect(result.major).toBe(1);
    expect(result.minor).toBe(5);
    expect(result.patch).toBe(10);
    expect(result.raw).toBe('v1.5.10');
  });

  it('parses version with suffix v1.5.10-sqwen36pre', () => {
    const result = parseVersion('v1.5.10-sqwen36pre');
    expect(result.major).toBe(1);
    expect(result.minor).toBe(5);
    expect(result.patch).toBe(10);
    expect(result.raw).toBe('v1.5.10-sqwen36pre');
  });

  it('parses v2.0.0', () => {
    const result = parseVersion('v2.0.0');
    expect(result.major).toBe(2);
    expect(result.minor).toBe(0);
    expect(result.patch).toBe(0);
  });

  it('parses v0.1.0', () => {
    const result = parseVersion('v0.1.0');
    expect(result.major).toBe(0);
    expect(result.minor).toBe(1);
    expect(result.patch).toBe(0);
  });

  it('throws on invalid version format', () => {
    expect(() => parseVersion('invalid')).toThrow('Invalid version format');
  });

  it('throws on partial version v1.5', () => {
    expect(() => parseVersion('v1.5')).toThrow('Invalid version format');
  });

  it('throws on empty string', () => {
    expect(() => parseVersion('')).toThrow('Invalid version format');
  });
});

describe('VersionSync.isCompatible()', () => {
  beforeEach(() => {
    vi.resetAllMocks();
  });

  it('returns true when major and minor match', async () => {
    const sync = new VersionSync({
      aiLtcRoot: '/fake/root',
      configPath: '/fake/config.json',
    });

    vi.spyOn(sync as any, 'readFrameworkVersion').mockResolvedValue('v1.5.10');
    vi.spyOn(sync as any, 'readConfigVersion').mockResolvedValue('v1.5.12');

    const result = await sync.isCompatible();
    expect(result).toBe(true);
  });

  it('returns false when major differs', async () => {
    const sync = new VersionSync({
      aiLtcRoot: '/fake/root',
      configPath: '/fake/config.json',
    });

    vi.spyOn(sync as any, 'readFrameworkVersion').mockResolvedValue('v1.5.10');
    vi.spyOn(sync as any, 'readConfigVersion').mockResolvedValue('v2.0.0');

    const result = await sync.isCompatible();
    expect(result).toBe(false);
  });

  it('returns false when minor differs', async () => {
    const sync = new VersionSync({
      aiLtcRoot: '/fake/root',
      configPath: '/fake/config.json',
    });

    vi.spyOn(sync as any, 'readFrameworkVersion').mockResolvedValue('v1.5.10');
    vi.spyOn(sync as any, 'readConfigVersion').mockResolvedValue('v1.6.0');

    const result = await sync.isCompatible();
    expect(result).toBe(false);
  });

  it('handles versions with suffixes', async () => {
    const sync = new VersionSync({
      aiLtcRoot: '/fake/root',
      configPath: '/fake/config.json',
    });

    vi.spyOn(sync as any, 'readFrameworkVersion').mockResolvedValue('v1.5.10-sqwen36pre');
    vi.spyOn(sync as any, 'readConfigVersion').mockResolvedValue('v1.5.10');

    const result = await sync.isCompatible();
    expect(result).toBe(true);
  });
});

describe('VersionSync.getDrift()', () => {
  beforeEach(() => {
    vi.resetAllMocks();
  });

  it('returns "none" when versions are identical', async () => {
    const sync = new VersionSync({
      aiLtcRoot: '/fake/root',
      configPath: '/fake/config.json',
    });

    vi.spyOn(sync as any, 'readFrameworkVersion').mockResolvedValue('v1.5.10');
    vi.spyOn(sync as any, 'readConfigVersion').mockResolvedValue('v1.5.10');

    const result = await sync.getDrift();
    expect(result.drift).toBe('none');
    expect(result.installed).toBe('v1.5.10');
    expect(result.available).toBe('v1.5.10');
  });

  it('returns "patch" when only patch differs', async () => {
    const sync = new VersionSync({
      aiLtcRoot: '/fake/root',
      configPath: '/fake/config.json',
    });

    vi.spyOn(sync as any, 'readFrameworkVersion').mockResolvedValue('v1.5.10');
    vi.spyOn(sync as any, 'readConfigVersion').mockResolvedValue('v1.5.15');

    const result = await sync.getDrift();
    expect(result.drift).toBe('patch');
  });

  it('returns "minor" when minor differs but major matches', async () => {
    const sync = new VersionSync({
      aiLtcRoot: '/fake/root',
      configPath: '/fake/config.json',
    });

    vi.spyOn(sync as any, 'readFrameworkVersion').mockResolvedValue('v1.5.10');
    vi.spyOn(sync as any, 'readConfigVersion').mockResolvedValue('v1.6.0');

    const result = await sync.getDrift();
    expect(result.drift).toBe('minor');
  });

  it('returns "major" when major differs', async () => {
    const sync = new VersionSync({
      aiLtcRoot: '/fake/root',
      configPath: '/fake/config.json',
    });

    vi.spyOn(sync as any, 'readFrameworkVersion').mockResolvedValue('v1.5.10');
    vi.spyOn(sync as any, 'readConfigVersion').mockResolvedValue('v2.0.0');

    const result = await sync.getDrift();
    expect(result.drift).toBe('major');
  });
});

describe('VersionSync.getLastCheck()', () => {
  it('returns null before check() is called', async () => {
    const sync = new VersionSync({
      aiLtcRoot: '/fake/root',
      configPath: '/fake/config.json',
    });

    expect(sync.getLastCheck()).toBeNull();
  });

  it('returns timestamp after check() is called', async () => {
    const sync = new VersionSync({
      aiLtcRoot: '/fake/root',
      configPath: '/fake/config.json',
    });

    vi.spyOn(sync as any, 'readFrameworkVersion').mockResolvedValue('v1.5.10');
    vi.spyOn(sync as any, 'readConfigVersion').mockResolvedValue('v1.5.10');

    await sync.check();
    expect(sync.getLastCheck()).not.toBeNull();
    expect(typeof sync.getLastCheck()).toBe('string');
  });
});
