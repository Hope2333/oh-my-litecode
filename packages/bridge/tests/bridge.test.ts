import { describe, it, expect, vi, beforeEach } from 'vitest';
import { OmlBridge } from '../src/bridge.js';
import { BridgeError } from '../src/types.js';
import type { BridgeConfig, AiLtcPhase } from '../src/types.js';

// ── Mock external modules ──────────────────────────────────────────────
vi.mock('@oml/core/hooks', () => ({
  triggerHook: vi.fn(),
}));

vi.mock('../src/config.js', () => ({
  BridgeConfigLoader: vi.fn(),
}));

vi.mock('../src/version-sync.js', () => ({
  VersionSync: vi.fn(),
}));

vi.mock('fs', () => ({
  default: {
    existsSync: vi.fn(),
    watch: vi.fn(),
    readFileSync: vi.fn(),
  },
  existsSync: vi.fn(),
  watch: vi.fn(),
  readFileSync: vi.fn(),
}));

// ── Import mocked modules ──────────────────────────────────────────────
import { triggerHook } from '@oml/core/hooks';
import { BridgeConfigLoader } from '../src/config.js';
import { VersionSync } from '../src/version-sync.js';
import * as fs from 'fs';

const mockTriggerHook = vi.mocked(triggerHook);
const MockBridgeConfigLoader = vi.mocked(BridgeConfigLoader);
const MockVersionSync = vi.mocked(VersionSync);
const mockExistsSync = vi.mocked(fs.existsSync);
const mockWatch = vi.mocked(fs.watch);
const mockReadFileSync = vi.mocked(fs.readFileSync);

// ── Helpers ────────────────────────────────────────────────────────────
function createMockConfig(overrides?: Partial<BridgeConfig>): BridgeConfig {
  return {
    enabled: true,
    aiLtcRoot: '/test/ai-ltc',
    configFile: '/test/.ai/system/ai-ltc-config.json',
    autoStart: false,
    logLevel: 'info',
    ...overrides,
  };
}

function setupMocks(config: BridgeConfig | null, compatible: boolean) {
  if (config !== null) {
    const mockLoader = { load: vi.fn().mockResolvedValue(config) };
    MockBridgeConfigLoader.mockReturnValue(mockLoader as unknown as InstanceType<typeof BridgeConfigLoader>);
  } else {
    const mockLoader = { load: vi.fn().mockResolvedValue(null) };
    MockBridgeConfigLoader.mockReturnValue(mockLoader as unknown as InstanceType<typeof BridgeConfigLoader>);
  }

  const mockVersionSync = {
    check: vi.fn().mockResolvedValue({
      framework: 'v0.2.0',
      bridge: 'v0.2.0',
      compatible,
      lastCheck: new Date().toISOString(),
    }),
  };
  MockVersionSync.mockReturnValue(mockVersionSync as unknown as InstanceType<typeof VersionSync>);
}

// ── Tests ──────────────────────────────────────────────────────────────
describe('OmlBridge', () => {
  beforeEach(() => {
    vi.resetAllMocks();
    vi.restoreAllMocks();
  });

  // ── initialize() ───────────────────────────────────────────────────
  describe('initialize()', () => {
    it('throws BridgeError when config loader fails', async () => {
      setupMocks(null, true);

      const bridge = new OmlBridge();

      await expect(bridge.initialize()).rejects.toBeInstanceOf(BridgeError);
    });

    it('throws BridgeError when version incompatible', async () => {
      setupMocks(createMockConfig(), false);

      const bridge = new OmlBridge();

      await expect(bridge.initialize()).rejects.toBeInstanceOf(BridgeError);
    });

    it('sets enabled=true when config loaded and version compatible', async () => {
      setupMocks(createMockConfig(), true);

      const bridge = new OmlBridge();
      await bridge.initialize();
      const status = await bridge.getStatus();

      expect(status.enabled).toBe(true);
    });
  });

  // ── transition() ───────────────────────────────────────────────────
  describe('transition()', () => {
    it('throws BridgeError when not initialized', async () => {
      const bridge = new OmlBridge();

      await expect(bridge.transition('EXECUTION' as AiLtcPhase)).rejects.toBeInstanceOf(BridgeError);
    });

    it('triggers correct hook for INIT → EXECUTION', async () => {
      setupMocks(createMockConfig(), true);

      const bridge = new OmlBridge();
      await bridge.initialize();
      await bridge.transition('EXECUTION');

      expect(mockTriggerHook).toHaveBeenCalledWith(
        'bridge:execution:start',
        expect.objectContaining({
          phase: 'EXECUTION',
          transition: 'INIT → EXECUTION',
        }),
      );
    });

    it('triggers correct hook for EXECUTION → REVIEW', async () => {
      setupMocks(createMockConfig(), true);

      const bridge = new OmlBridge();
      await bridge.initialize();
      await bridge.transition('EXECUTION');
      mockTriggerHook.mockClear();
      await bridge.transition('REVIEW');

      expect(mockTriggerHook).toHaveBeenCalledWith(
        'bridge:review:start',
        expect.objectContaining({
          phase: 'REVIEW',
          transition: 'EXECUTION → REVIEW',
        }),
      );
    });

    it('returns silently when no mapping found', async () => {
      setupMocks(createMockConfig(), true);

      const bridge = new OmlBridge();
      await bridge.initialize();

      // No mapping targets INIT as a destination phase
      await expect(bridge.transition('INIT' as AiLtcPhase)).resolves.toBeUndefined();
    });

    it('updates currentPhase after successful transition', async () => {
      setupMocks(createMockConfig(), true);

      const bridge = new OmlBridge();
      await bridge.initialize();
      await bridge.transition('EXECUTION');

      const status = await bridge.getStatus();
      expect(status.phase).toBe('EXECUTION');
    });
  });

  // ── getStatus() ────────────────────────────────────────────────────
  describe('getStatus()', () => {
    it('returns enabled=false before initialization', async () => {
      const bridge = new OmlBridge();
      const status = await bridge.getStatus();

      expect(status.enabled).toBe(false);
      expect(status.phase).toBeNull();
      expect(status.config).toBeNull();
    });

    it('returns enabled=true, phase, config after initialization', async () => {
      const config = createMockConfig();
      setupMocks(config, true);

      const bridge = new OmlBridge();
      await bridge.initialize();
      const status = await bridge.getStatus();

      expect(status.enabled).toBe(true);
      expect(status.config).toEqual(config);
    });
  });

  // ── start() ────────────────────────────────────────────────────────
  describe('start()', () => {
    it('throws BridgeError when not initialized', async () => {
      const bridge = new OmlBridge();

      await expect(bridge.start()).rejects.toBeInstanceOf(BridgeError);
    });

    it('returns early when not enabled', async () => {
      setupMocks(createMockConfig({ enabled: false }), true);

      const bridge = new OmlBridge();
      await bridge.initialize();

      await expect(bridge.start()).resolves.toBeUndefined();
    });

    it('warns when state file not found', async () => {
      setupMocks(createMockConfig(), true);
      mockExistsSync.mockReturnValue(false);
      const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});

      const bridge = new OmlBridge();
      await bridge.initialize();
      await bridge.start();

      expect(warnSpy).toHaveBeenCalledWith(
        expect.stringContaining('State file not found'),
      );

      warnSpy.mockRestore();
    });
  });

  // ── dispose() ──────────────────────────────────────────────────────
  describe('dispose()', () => {
    it('clears config, enabled, currentPhase', async () => {
      setupMocks(createMockConfig(), true);

      const bridge = new OmlBridge();
      await bridge.initialize();
      await bridge.transition('EXECUTION');

      await bridge.dispose();
      const status = await bridge.getStatus();

      expect(status.enabled).toBe(false);
      expect(status.phase).toBeNull();
      expect(status.config).toBeNull();
    });

    it('stops watcher', async () => {
      setupMocks(createMockConfig(), true);
      mockExistsSync.mockReturnValue(true);
      mockWatch.mockReturnValue({ close: vi.fn() } as unknown as fs.FSWatcher);
      mockReadFileSync.mockReturnValue(JSON.stringify({ phase: 'EXECUTION' }));

      const bridge = new OmlBridge();
      await bridge.initialize();
      await bridge.start();

      await bridge.dispose();
      const status = await bridge.getStatus();

      expect(status.enabled).toBe(false);
      expect(status.config).toBeNull();
    });
  });
});
