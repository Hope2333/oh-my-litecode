import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

// ── Mock external modules BEFORE importing bridge code ─────────────────
vi.mock('@oml/core/hooks', () => ({
  triggerHook: vi.fn().mockResolvedValue(undefined),
}));

vi.mock('../src/config.js', () => ({
  BridgeConfigLoader: vi.fn(),
}));

vi.mock('../src/version-sync.js', async (importOriginal) => {
  const actual = await importOriginal() as Record<string, unknown>;
  return {
    ...actual,
    VersionSync: vi.fn(),
  };
});

vi.mock('fs', () => ({
  default: {
    existsSync: vi.fn(),
    watch: vi.fn(),
    readFileSync: vi.fn(),
    writeFileSync: vi.fn(),
    appendFileSync: vi.fn(),
  },
  existsSync: vi.fn(),
  watch: vi.fn(),
  readFileSync: vi.fn(),
  writeFileSync: vi.fn(),
  appendFileSync: vi.fn(),
}));

// ── Import modules under test ──────────────────────────────────────────
import { OmlBridge } from '../src/bridge.js';
import { BridgeError } from '../src/types.js';
import type { BridgeConfig, AiLtcPhase } from '../src/types.js';
import { EventMapper } from '../src/events.js';
import { parseVersion, VersionSync } from '../src/version-sync.js';
import * as fs from 'fs';
import { triggerHook } from '@oml/core/hooks';
import { BridgeConfigLoader } from '../src/config.js';

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

function setupVersionSync(compatible: boolean, frameworkVersion = 'v1.5.10', bridgeVersion = 'v1.5.12') {
  const mockVersionSync = {
    check: vi.fn().mockResolvedValue({
      framework: frameworkVersion,
      bridge: bridgeVersion,
      compatible,
      lastCheck: new Date().toISOString(),
    }),
    isCompatible: vi.fn().mockResolvedValue(compatible),
    getDrift: vi.fn().mockResolvedValue({
      installed: frameworkVersion,
      available: bridgeVersion,
      drift: compatible ? 'none' : 'minor',
    }),
    getLastCheck: vi.fn().mockReturnValue(new Date().toISOString()),
  };
  MockVersionSync.mockReturnValue(mockVersionSync as unknown as InstanceType<typeof VersionSync>);
}

function setupConfigLoader(config: BridgeConfig | null) {
  if (config !== null) {
    const mockLoader = { load: vi.fn().mockResolvedValue(config) };
    MockBridgeConfigLoader.mockReturnValue(mockLoader as unknown as InstanceType<typeof BridgeConfigLoader>);
  } else {
    const mockLoader = { load: vi.fn().mockResolvedValue(null) };
    MockBridgeConfigLoader.mockReturnValue(mockLoader as unknown as InstanceType<typeof BridgeConfigLoader>);
  }
}

function resetAllMocks() {
  vi.resetAllMocks();
  vi.restoreAllMocks();
  mockTriggerHook.mockResolvedValue(undefined);
}

// ── Integration Tests ──────────────────────────────────────────────────
describe('Bridge Integration Flow', () => {
  beforeEach(() => {
    resetAllMocks();
  });

  afterEach(async () => {
    // Ensure clean state between tests
    vi.clearAllTimers();
  });

  // ── Full lifecycle: initialize → transition → hooks → memory ──────
  describe('full bridge lifecycle', () => {
    it('initializes, transitions through phases, and fires hooks in order', async () => {
      const config = createMockConfig();
      setupConfigLoader(config);
      setupVersionSync(true);

      const bridge = new OmlBridge();

      // 1. Initialize bridge
      await bridge.initialize();
      const statusAfterInit = await bridge.getStatus();
      expect(statusAfterInit.enabled).toBe(true);
      expect(statusAfterInit.phase).toBeNull();
      expect(statusAfterInit.config).toEqual(config);

      // 2. Transition: INIT → EXECUTION
      await bridge.transition('EXECUTION', { sessionId: 'sess-001', goal: 'Build feature' });
      expect(mockTriggerHook).toHaveBeenCalledTimes(1);
      expect(mockTriggerHook).toHaveBeenCalledWith(
        'bridge:execution:start',
        expect.objectContaining({
          phase: 'EXECUTION',
          transition: 'INIT → EXECUTION',
          sessionId: 'sess-001',
          goal: 'Build feature',
        }),
      );

      // 3. Transition: EXECUTION → REVIEW
      mockTriggerHook.mockClear();
      await bridge.transition('REVIEW', { sessionId: 'sess-001', artifacts: 'src/index.ts' });
      expect(mockTriggerHook).toHaveBeenCalledTimes(1);
      expect(mockTriggerHook).toHaveBeenCalledWith(
        'bridge:review:start',
        expect.objectContaining({
          phase: 'REVIEW',
          transition: 'EXECUTION → REVIEW',
          sessionId: 'sess-001',
          artifacts: 'src/index.ts',
        }),
      );

      // 4. Transition: REVIEW → OPTIMIZER
      mockTriggerHook.mockClear();
      await bridge.transition('OPTIMIZER', { sessionId: 'sess-001', reviewFindings: 'Optimize loops' });
      expect(mockTriggerHook).toHaveBeenCalledTimes(1);
      expect(mockTriggerHook).toHaveBeenCalledWith(
        'bridge:optimize:start',
        expect.objectContaining({
          phase: 'OPTIMIZER',
          transition: 'REVIEW → OPTIMIZER',
          sessionId: 'sess-001',
          reviewFindings: 'Optimize loops',
        }),
      );

      // 5. Transition: OPTIMIZER → CHECKPOINT
      mockTriggerHook.mockClear();
      await bridge.transition('CHECKPOINT', { sessionId: 'sess-001', summary: 'All done', metrics: '100%' });
      expect(mockTriggerHook).toHaveBeenCalledTimes(1);
      expect(mockTriggerHook).toHaveBeenCalledWith(
        'bridge:checkpoint:create',
        expect.objectContaining({
          phase: 'CHECKPOINT',
          transition: 'OPTIMIZER → CHECKPOINT',
          sessionId: 'sess-001',
          summary: 'All done',
          metrics: '100%',
        }),
      );

      // 6. Verify final state
      const finalStatus = await bridge.getStatus();
      expect(finalStatus.phase).toBe('CHECKPOINT');
    });

    it('tracks phase transitions correctly across multiple hops', async () => {
      const config = createMockConfig();
      setupConfigLoader(config);
      setupVersionSync(true);

      const bridge = new OmlBridge();
      await bridge.initialize();

      const phases: AiLtcPhase[] = ['EXECUTION', 'REVIEW', 'EXECUTION', 'BLOCKED'];
      const expectedHooks = [
        'bridge:execution:start',
        'bridge:review:start',
        'bridge:blocked:resolve',
        'bridge:blocked:notify',
      ];

      for (let i = 0; i < phases.length; i++) {
        mockTriggerHook.mockClear();
        await bridge.transition(phases[i]);

        if (expectedHooks[i]) {
          expect(mockTriggerHook).toHaveBeenCalledWith(
            expectedHooks[i],
            expect.objectContaining({ phase: phases[i] }),
          );
        }
      }

      const status = await bridge.getStatus();
      expect(status.phase).toBe('BLOCKED');
    });
  });

  // ── Error tracking integration ─────────────────────────────────────
  describe('error tracking integration', () => {
    it('throws BridgeError with correct code on version incompatibility', async () => {
      const config = createMockConfig();
      setupConfigLoader(config);
      setupVersionSync(false, 'v1.5.10', 'v2.0.0');

      const bridge = new OmlBridge();

      await expect(bridge.initialize()).rejects.toSatisfy((err: unknown) => {
        if (!(err instanceof BridgeError)) return false;
        expect(err.code).toBe('VERSION_INCOMPATIBLE');
        expect(err.message).toContain('v1.5.10');
        expect(err.message).toContain('v2.0.0');
        return true;
      });
    });

    it('throws BridgeError when config fails to load', async () => {
      setupConfigLoader(null);
      setupVersionSync(true);

      const bridge = new OmlBridge();

      await expect(bridge.initialize()).rejects.toSatisfy((err: unknown) => {
        if (!(err instanceof BridgeError)) return false;
        expect(err.code).toBe('OML_UNAVAILABLE');
        return true;
      });
    });

    it('throws BridgeError on transition before initialization', async () => {
      const bridge = new OmlBridge();

      await expect(bridge.transition('EXECUTION')).rejects.toBeInstanceOf(BridgeError);
    });

    it('throws BridgeError on start before initialization', async () => {
      const bridge = new OmlBridge();

      await expect(bridge.start()).rejects.toBeInstanceOf(BridgeError);
    });
  });

  // ── Hook firing verification ───────────────────────────────────────
  describe('hook firing verification', () => {
    it('fires hook with timestamp and transition string', async () => {
      const config = createMockConfig();
      setupConfigLoader(config);
      setupVersionSync(true);

      const bridge = new OmlBridge();
      await bridge.initialize();
      await bridge.transition('EXECUTION');

      const hookCall = mockTriggerHook.mock.calls[0];
      const payload = hookCall[1]!;

      expect(payload.timestamp).toBeInstanceOf(Date);
      expect(payload.transition).toBe('INIT → EXECUTION');
      expect(payload.phase).toBe('EXECUTION');
    });

    it('merges custom data into hook payload', async () => {
      const config = createMockConfig();
      setupConfigLoader(config);
      setupVersionSync(true);

      const bridge = new OmlBridge();
      await bridge.initialize();

      const customData = {
        customField: 'custom-value',
        nested: { key: 'value' },
        count: 42,
      };

      await bridge.transition('REVIEW', customData);

      const payload = mockTriggerHook.mock.calls[0][1]!;
      expect(payload.customField).toBe('custom-value');
      expect(payload.nested).toEqual({ key: 'value' });
      expect(payload.count).toBe(42);
      expect(payload.phase).toBe('REVIEW');
    });

    it('falls back to BLOCKED hook when no exact mapping exists for destination', async () => {
      const config = createMockConfig();
      setupConfigLoader(config);
      setupVersionSync(true);

      const bridge = new OmlBridge();
      await bridge.initialize();

      // INIT as destination has no exact mapping, falls back to Any → BLOCKED
      await bridge.transition('INIT' as AiLtcPhase);

      expect(mockTriggerHook).toHaveBeenCalledWith(
        'bridge:blocked:notify',
        expect.objectContaining({ phase: 'INIT' }),
      );
    });
  });

  // ── State file watching integration ────────────────────────────────
  describe('state file watching integration', () => {
    it('starts watcher when state file exists and enabled', async () => {
      const config = createMockConfig();
      setupConfigLoader(config);
      setupVersionSync(true);

      mockExistsSync.mockReturnValue(true);
      mockReadFileSync.mockReturnValue(JSON.stringify({ phase: 'INIT' }));
      const mockWatcher = { close: vi.fn() };
      mockWatch.mockReturnValue(mockWatcher as unknown as fs.FSWatcher);

      const bridge = new OmlBridge({ aiLtcRoot: '/test/ai-ltc' });
      await bridge.initialize();
      await bridge.start();

      expect(mockExistsSync).toHaveBeenCalled();
      expect(mockWatch).toHaveBeenCalled();
      expect(mockReadFileSync).toHaveBeenCalled();

      await bridge.dispose();
      expect(mockWatcher.close).toHaveBeenCalled();
    });

    it('does not start watcher when disabled', async () => {
      const config = createMockConfig({ enabled: false });
      setupConfigLoader(config);
      setupVersionSync(true);

      const bridge = new OmlBridge();
      await bridge.initialize();
      await bridge.start();

      expect(mockExistsSync).not.toHaveBeenCalled();
      expect(mockWatch).not.toHaveBeenCalled();
    });
  });

  // ── EventMapper + Bridge integration ───────────────────────────────
  describe('EventMapper + Bridge integration', () => {
    it('all defined transitions produce correct hooks through the bridge', async () => {
      const config = createMockConfig();
      setupConfigLoader(config);
      setupVersionSync(true);

      const bridge = new OmlBridge();
      await bridge.initialize();

      const mapper = new EventMapper();
      const mappings = mapper.getEventMap();

      // Test each mapping that has a reachable target phase
      const testCases: { from: AiLtcPhase | null; to: AiLtcPhase; expectedHook: string }[] = [
        { from: null, to: 'EXECUTION', expectedHook: 'bridge:execution:start' },
        { from: 'EXECUTION', to: 'REVIEW', expectedHook: 'bridge:review:start' },
      ];

      for (const tc of testCases) {
        mockTriggerHook.mockClear();

        // Set up the from-phase by transitioning to it first (if needed)
        if (tc.from) {
          // Reset bridge state by creating new instance
          const freshBridge = new OmlBridge();
          await freshBridge.initialize();
          await freshBridge.transition(tc.from);

          mockTriggerHook.mockClear();
          await freshBridge.transition(tc.to);

          expect(mockTriggerHook).toHaveBeenCalledWith(
            tc.expectedHook,
            expect.objectContaining({ phase: tc.to }),
          );
        } else {
          await bridge.transition(tc.to);

          expect(mockTriggerHook).toHaveBeenCalledWith(
            tc.expectedHook,
            expect.objectContaining({ phase: tc.to }),
          );
        }
      }
    });
  });

  // ── VersionSync integration ────────────────────────────────────────
  describe('VersionSync integration', () => {
    it('VersionSync.check() returns complete version info', async () => {
      setupVersionSync(true, 'v1.5.10', 'v1.5.12');

      const sync = new VersionSync({
        aiLtcRoot: '/test/ai-ltc',
        configPath: '/test/.ai/system/ai-ltc-config.json',
      });

      const info = await sync.check();
      expect(info.compatible).toBe(true);
      expect(info.framework).toBe('v1.5.10');
      expect(info.bridge).toBe('v1.5.12');
      expect(info.lastCheck).toBeDefined();
    });

    it('parseVersion handles all version formats used in the codebase', () => {
      const testCases = [
        { raw: 'v1.5.10', major: 1, minor: 5, patch: 10 },
        { raw: 'v1.5.10-sqwen36pre', major: 1, minor: 5, patch: 10 },
        { raw: 'v0.2.0', major: 0, minor: 2, patch: 0 },
        { raw: 'v2.0.0-alpha', major: 2, minor: 0, patch: 0 },
      ];

      for (const tc of testCases) {
        const result = parseVersion(tc.raw);
        expect(result.major).toBe(tc.major);
        expect(result.minor).toBe(tc.minor);
        expect(result.patch).toBe(tc.patch);
        expect(result.raw).toBe(tc.raw);
      }
    });
  });

  // ── Dispose and cleanup ────────────────────────────────────────────
  describe('dispose and cleanup', () => {
    it('full lifecycle: init → transitions → dispose cleans up properly', async () => {
      const config = createMockConfig();
      setupConfigLoader(config);
      setupVersionSync(true);

      mockExistsSync.mockReturnValue(true);
      mockReadFileSync.mockReturnValue(JSON.stringify({ phase: 'EXECUTION' }));
      const mockWatcher = { close: vi.fn() };
      mockWatch.mockReturnValue(mockWatcher as unknown as fs.FSWatcher);

      const bridge = new OmlBridge();
      await bridge.initialize();
      await bridge.transition('EXECUTION');
      await bridge.start();

      // Verify running state
      const runningStatus = await bridge.getStatus();
      expect(runningStatus.enabled).toBe(true);
      expect(runningStatus.phase).toBe('EXECUTION');

      // Dispose
      await bridge.dispose();

      // Verify cleaned up
      const disposedStatus = await bridge.getStatus();
      expect(disposedStatus.enabled).toBe(false);
      expect(disposedStatus.phase).toBeNull();
      expect(disposedStatus.config).toBeNull();
      expect(mockWatcher.close).toHaveBeenCalled();
    });
  });
});
