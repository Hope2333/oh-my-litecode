import * as fs from 'fs';
import * as path from 'path';
import type { BridgeConfig } from './types.js';

export { BridgeConfig };

export interface BridgeConfigLoaderOptions {
  projectRoot?: string;
  configPath?: string;
}

export class BridgeConfigLoader {
  private projectRoot: string;
  private configPath: string;
  private cached: BridgeConfig | null = null;

  constructor(options?: BridgeConfigLoaderOptions) {
    this.projectRoot = options?.projectRoot ?? process.cwd();
    this.configPath =
      options?.configPath ?? path.join('.ai', 'system', 'ai-ltc-config.json');
  }

  private get fullPath(): string {
    return path.isAbsolute(this.configPath)
      ? this.configPath
      : path.join(this.projectRoot, this.configPath);
  }

  async loadRaw(): Promise<Record<string, unknown>> {
    const fullPath = this.fullPath;

    try {
      const content = await fs.promises.readFile(fullPath, 'utf-8');
      return JSON.parse(content) as Record<string, unknown>;
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code === 'ENOENT') {
        throw new Error('AI-LTC config not found');
      }
      throw err;
    }
  }

  async load(): Promise<BridgeConfig> {
    if (this.cached) return this.cached;

    const raw = await this.loadRaw();

    const observability = (raw.observability ?? {}) as Record<string, unknown>;
    const logLevel = (observability.log_level as string) ?? 'info';

    this.cached = {
      enabled: true,
      aiLtcRoot: (raw.folder_root as string) ?? '',
      configFile: this.fullPath,
      autoStart: false,
      logLevel: logLevel as BridgeConfig['logLevel'],
    };

    return this.cached;
  }

  async reload(): Promise<BridgeConfig> {
    this.cached = null;
    return this.load();
  }

  async getFrameworkVersion(): Promise<string> {
    const raw = await this.loadRaw();
    return (raw.framework_version as string) ?? '';
  }

  async getAiLtcRoot(): Promise<string> {
    const raw = await this.loadRaw();
    return (raw.folder_root as string) ?? '';
  }

  async isExperimental(): Promise<boolean> {
    const raw = await this.loadRaw();
    const experimental = (raw.experimental_mode ?? {}) as Record<string, unknown>;
    return (experimental.enabled as boolean) ?? false;
  }

  async getResolverNote(): Promise<string> {
    const raw = await this.loadRaw();
    return (raw.resolver_note as string) ?? '';
  }
}

let defaultLoader: BridgeConfigLoader | null = null;

function getDefaultLoader(): BridgeConfigLoader {
  if (!defaultLoader) {
    defaultLoader = new BridgeConfigLoader();
  }
  return defaultLoader;
}

export const loadBridgeConfig = () => getDefaultLoader().load();
