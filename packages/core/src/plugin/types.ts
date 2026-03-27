/**
 * Plugin Types - OML Core
 * 
 * Type definitions for plugin system.
 */

export type PluginType = 'agent' | 'subagent' | 'mcp' | 'skill';

export type PluginStatus = 'enabled' | 'disabled' | 'installed';

export interface Plugin {
  name: string;
  type: PluginType;
  version: string;
  description: string;
  author?: string;
  status: PluginStatus;
  path: string;
  mainScript?: string;
  dependencies?: string[];
  config?: Record<string, unknown>;
  installedAt: Date;
  enabledAt?: Date;
}

export interface PluginInstallOptions {
  source: string; // URL or local path
  type?: PluginType;
  enable?: boolean;
}

export interface PluginCreateOptions {
  name: string;
  type: PluginType;
  description?: string;
  author?: string;
}

export interface PluginRunOptions {
  args?: string[];
  env?: Record<string, string>;
  timeout?: number;
}

export interface PluginRunResult {
  success: boolean;
  output: string;
  error?: string;
  exitCode: number;
}
