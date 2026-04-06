import * as fs from 'node:fs';
import * as path from 'node:path';
import type { PlatformAdapter } from './index.js';

export class ClaudeCodeAdapter implements PlatformAdapter {
  name = 'claude-code';
  version = '0.2.0';

  private stateFile: string;
  private initialized = false;

  constructor(projectRoot?: string) {
    const root = projectRoot ?? process.cwd();
    this.stateFile = path.join(root, '.ai', 'claude-state.json');
  }

  async initialize(): Promise<void> {
    if (this.initialized) return;

    const dir = path.dirname(this.stateFile);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }

    if (!fs.existsSync(this.stateFile)) {
      await fs.promises.writeFile(
        this.stateFile,
        JSON.stringify({ phase: 'INIT', timestamp: new Date().toISOString() }, null, 2),
      );
    }

    this.initialized = true;
  }

  async teardown(): Promise<void> {
    this.initialized = false;
  }

  async syncState(phase: string): Promise<void> {
    const raw = await this._readState();
    const state = raw ?? {};
    state.phase = phase;
    state.timestamp = new Date().toISOString();
    state.lastUpdatedBy = 'claude-adapter';
    await fs.promises.writeFile(this.stateFile, JSON.stringify(state, null, 2));
  }

  async getState(): Promise<string | null> {
    const state = await this._readState();
    return (state?.phase as string | undefined) ?? null;
  }

  async forwardEvent(event: { type: string; payload: Record<string, unknown> }): Promise<void> {
    console.log(`[claude-adapter] Event forwarded: ${event.type}`, event.payload);
  }

  getCapabilities() {
    return {
      supportsRealtime: false,
      supportsHistory: true,
      supportsContext: true,
    };
  }

  private async _readState(): Promise<Record<string, unknown> | null> {
    try {
      const content = await fs.promises.readFile(this.stateFile, 'utf-8');
      return JSON.parse(content) as Record<string, unknown>;
    } catch {
      return null;
    }
  }
}
