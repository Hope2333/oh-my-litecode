import * as fs from 'fs';
import * as path from 'path';
import { triggerHook } from '@oml/core/hooks';
import type { HookEvent } from '@oml/core/hooks';
import { EventMapper } from './events.js';
import type { BridgeConfig, AiLtcPhase } from './types.js';
import { BridgeError } from './types.js';
import { BridgeConfigLoader } from './config.js';
import { VersionSync } from './version-sync.js';

interface OmlBridgeOptions {
  projectRoot?: string;
  configPath?: string;
  aiLtcRoot?: string;
}

export class OmlBridge {
  private config: BridgeConfig | null = null;
  private eventMapper: EventMapper;
  private enabled: boolean = false;
  private currentPhase: AiLtcPhase | null = null;
  private stateFile: string;
  private watcher: fs.FSWatcher | null = null;
  private debounceTimer: NodeJS.Timeout | null = null;

  constructor(options: OmlBridgeOptions = {}) {
    const projectRoot = options.projectRoot ?? process.cwd();
    this.eventMapper = new EventMapper();
    this.stateFile = options.aiLtcRoot
      ? path.join(options.aiLtcRoot, '.ai', 'state.json')
      : path.join(projectRoot, '.ai', 'state.json');
  }

  async initialize(): Promise<void> {
    const loader = new BridgeConfigLoader({ projectRoot: process.cwd() });
    this.config = await loader.load();

    if (!this.config) {
      throw new BridgeError(
        'OML_UNAVAILABLE',
        'Bridge configuration could not be loaded',
        'Ensure bridge config file exists and is valid JSON',
        false
      );
    }

    const versionSync = new VersionSync({
      aiLtcRoot: this.config.aiLtcRoot,
      configPath: this.config.configFile,
    });
    const compatibility = await versionSync.check();

    if (!compatibility.compatible) {
      throw new BridgeError(
        'VERSION_INCOMPATIBLE',
        `Bridge version incompatible: framework=${compatibility.framework}, bridge=${compatibility.bridge}`,
        `AI-LTC: ${compatibility.framework}, Bridge: ${compatibility.bridge}`,
        false
      );
    }

    this.enabled = this.config.enabled;
  }

  /**
   * Trigger the mapped hook event for a phase transition.
   */
  async transition(newPhase: AiLtcPhase, data?: Record<string, unknown>): Promise<void> {
    if (!this.config) {
      throw new BridgeError(
        'OML_UNAVAILABLE',
        'Bridge not initialized — config not loaded',
        'Call initialize() before transition()',
        false
      );
    }

    const fromPhase = this.currentPhase ?? 'INIT';
    const transitionStr = `${fromPhase} → ${newPhase}`;

    // Try exact match first
    let mapping = this.eventMapper.mapTransitionToHook(transitionStr);

    // Fallback: wildcard — find any mapping whose hook starts with 'bridge:'
    // and whose transition target matches the newPhase
    if (!mapping) {
      mapping = this.eventMapper.findWildcardMapping(newPhase);
    }

    if (!mapping) {
      return;
    }

    const hook = mapping.hook as HookEvent;

    await triggerHook(hook, {
      phase: newPhase,
      transition: transitionStr,
      timestamp: new Date(),
      ...data,
    });

    this.currentPhase = newPhase;
  }

  /**
   * Get current bridge status.
   */
  async getStatus(): Promise<{
    enabled: boolean;
    phase: string | null;
    config: BridgeConfig | null;
  }> {
    return {
      enabled: this.enabled,
      phase: this.currentPhase,
      config: this.config,
    };
  }

  /**
   * Begin watching .ai/state.json for phase changes (opt-in).
   */
  async start(): Promise<void> {
    if (!this.config) {
      throw new BridgeError(
        'OML_UNAVAILABLE',
        'Bridge not initialized',
        'Call initialize() before start()',
        false
      );
    }

    if (!this.enabled) {
      return;
    }

    if (!fs.existsSync(this.stateFile)) {
      console.warn(`[OmlBridge] State file not found: ${this.stateFile}`);
      this.enabled = false;
      return;
    }

    // Read initial phase
    try {
      const raw = fs.readFileSync(this.stateFile, 'utf-8');
      const state = JSON.parse(raw);
      this.currentPhase = state.phase ?? null;
    } catch {
      console.warn(`[OmlBridge] Failed to read initial state from ${this.stateFile}`);
    }

    // Watch for changes with debounce
    this.watcher = fs.watch(path.dirname(this.stateFile), (eventType, filename) => {
      if (filename !== path.basename(this.stateFile)) return;
      if (eventType !== 'change') return;

      if (this.debounceTimer) clearTimeout(this.debounceTimer);
      this.debounceTimer = setTimeout(() => {
        this._onStateFileChange().catch((err) => {
          console.error('[OmlBridge] Error handling state file change:', err);
        });
      }, 100);
    });
  }

  /**
   * Stop watching for state file changes.
   */
  async stop(): Promise<void> {
    if (this.watcher) {
      this.watcher.close();
      this.watcher = null;
    }
  }

  /**
   * Full cleanup — stop watcher and release resources.
   */
  async dispose(): Promise<void> {
    await this.stop();
    this.config = null;
    this.enabled = false;
    this.currentPhase = null;
  }

  /**
   * Internal handler for state file change events.
   */
  private async _onStateFileChange(): Promise<void> {
    try {
      const raw = fs.readFileSync(this.stateFile, 'utf-8');
      const state = JSON.parse(raw);
      const newPhase: AiLtcPhase | null = state.phase ?? null;

      if (newPhase && newPhase !== this.currentPhase) {
        await this.transition(newPhase);
      }
    } catch (err) {
      console.error('[OmlBridge] Failed to parse state file:', err);
    }
  }
}
