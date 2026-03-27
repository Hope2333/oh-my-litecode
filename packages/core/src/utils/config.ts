/**
 * Config Module - OML Core
 * 
 * Provides configuration loading and management.
 */

import { z } from 'zod';
import * as fs from 'fs';
import * as path from 'path';

// Configuration schema
export const ConfigSchema = z.object({
  version: z.string(),
  projectName: z.string(),
  projectState: z.string(),
  sourceMode: z.enum(['local', 'remote']),
  localPath: z.string().optional(),
  resolver: z.object({
    primaryModel: z.string(),
    architectModel: z.string(),
    optimizerModel: z.string(),
    language: z.string(),
    outputFormat: z.string(),
  }),
  activeLane: z.object({
    name: z.string(),
    status: z.string(),
    stage: z.string().optional(),
    owner: z.string(),
    nextAction: z.string(),
    blockers: z.array(z.string()),
    boundedPass: z.number(),
  }),
  guardrails: z.object({
    boundedPassLimit: z.number(),
    escalationThreshold: z.string(),
    stopPhrases: z.array(z.string()),
  }),
});

export type Config = z.infer<typeof ConfigSchema>;

// Configuration loader
export class ConfigLoader {
  private config: Config | null = null;
  private configPath: string;

  constructor(configPath?: string) {
    this.configPath = configPath ?? this.getDefaultConfigPath();
  }

  private getDefaultConfigPath(): string {
    return path.join(process.cwd(), '.ai', 'system', 'ai-ltc-config.json');
  }

  async load(): Promise<Config> {
    if (this.config) {
      return this.config;
    }

    try {
      const content = await fs.promises.readFile(this.configPath, 'utf-8');
      const parsed = JSON.parse(content);
      this.config = ConfigSchema.parse(parsed);
      return this.config;
    } catch (error) {
      if (error instanceof z.ZodError) {
        throw new Error(`Invalid config: ${error.errors.map(e => e.message).join(', ')}`);
      }
      throw new Error(`Failed to load config from ${this.configPath}: ${error}`);
    }
  }

  async reload(): Promise<Config> {
    this.config = null;
    return this.load();
  }

  getConfig(): Config | null {
    return this.config;
  }

  async get<T extends keyof Config>(key: T): Promise<Config[T]> {
    const config = await this.load();
    return config[key];
  }

  async update<T extends keyof Config>(key: T, value: Config[T]): Promise<void> {
    const config = await this.load();
    config[key] = value;
    
    await fs.promises.writeFile(
      this.configPath,
      JSON.stringify(config, null, 2),
      'utf-8'
    );
    
    this.config = config;
  }
}

// Default config loader instance
let defaultLoader: ConfigLoader | null = null;

export function getDefaultConfigLoader(): ConfigLoader {
  if (!defaultLoader) {
    defaultLoader = new ConfigLoader();
  }
  return defaultLoader;
}

// Convenience functions
export const loadConfig = () => getDefaultConfigLoader().load();
export const reloadConfig = () => getDefaultConfigLoader().reload();
export const getConfig = () => getDefaultConfigLoader().getConfig();
