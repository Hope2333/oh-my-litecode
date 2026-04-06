import { describe, it, expect, beforeEach } from 'vitest';
import { AdapterRegistry } from '../src/adapters/index.js';
import { OpenCodeAdapter } from '../src/adapters/opencode-adapter.js';
import { ClaudeCodeAdapter } from '../src/adapters/claude-adapter.js';

describe('AdapterRegistry', () => {
  let registry: AdapterRegistry;

  beforeEach(() => {
    registry = new AdapterRegistry();
  });

  // ── register ───────────────────────────────────────────────────
  describe('register', () => {
    it('adds adapter to registry', () => {
      const adapter = new OpenCodeAdapter('/tmp');
      registry.register(adapter);

      expect(registry.get('opencode')).toBe(adapter);
    });
  });

  // ── get ────────────────────────────────────────────────────────
  describe('get', () => {
    it('retrieves adapter by name', () => {
      const adapter = new OpenCodeAdapter('/tmp');
      registry.register(adapter);

      const retrieved = registry.get('opencode');
      expect(retrieved).toBe(adapter);
    });

    it('returns undefined for unknown adapter', () => {
      expect(registry.get('nonexistent')).toBeUndefined();
    });
  });

  // ── list ───────────────────────────────────────────────────────
  describe('list', () => {
    it('returns all registered adapters', () => {
      registry.register(new OpenCodeAdapter('/tmp'));
      registry.register(new ClaudeCodeAdapter('/tmp'));

      const adapters = registry.list();
      expect(adapters).toHaveLength(2);
      const names = adapters.map((a) => a.name);
      expect(names).toContain('opencode');
      expect(names).toContain('claude-code');
    });

    it('returns empty array when no adapters registered', () => {
      expect(registry.list()).toEqual([]);
    });
  });

  // ── setActive / getActive ──────────────────────────────────────
  describe('setActive / getActive', () => {
    it('sets and gets active adapter', () => {
      registry.register(new OpenCodeAdapter('/tmp'));
      registry.setActive('opencode');

      const active = registry.getActive();
      expect(active).not.toBeNull();
      expect(active!.name).toBe('opencode');
    });

    it('returns null when no active adapter set', () => {
      expect(registry.getActive()).toBeNull();
    });

    it('throws when setting unregistered adapter as active', () => {
      expect(() => registry.setActive('nonexistent')).toThrow(
        'Adapter "nonexistent" not registered',
      );
    });
  });
});

describe('OpenCodeAdapter', () => {
  it('has correct name and version', () => {
    const adapter = new OpenCodeAdapter('/tmp');
    expect(adapter.name).toBe('opencode');
    expect(adapter.version).toBe('0.2.0');
  });

  it('getCapabilities returns correct capabilities', () => {
    const adapter = new OpenCodeAdapter('/tmp');
    const caps = adapter.getCapabilities();

    expect(caps).toEqual({
      supportsRealtime: true,
      supportsHistory: true,
      supportsContext: true,
    });
  });
});

describe('ClaudeCodeAdapter', () => {
  it('has correct name and version', () => {
    const adapter = new ClaudeCodeAdapter('/tmp');
    expect(adapter.name).toBe('claude-code');
    expect(adapter.version).toBe('0.2.0');
  });

  it('getCapabilities returns correct capabilities', () => {
    const adapter = new ClaudeCodeAdapter('/tmp');
    const caps = adapter.getCapabilities();

    expect(caps).toEqual({
      supportsRealtime: false,
      supportsHistory: true,
      supportsContext: true,
    });
  });
});
