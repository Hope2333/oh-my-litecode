/**
 * OML Plugin Types
 * 
 * Type definitions for plugin system
 */

export type PluginType = 'agent' | 'subagent' | 'mcp' | 'skill' | 'core';

export type PluginStatus = 'enabled' | 'disabled' | 'installed' | 'not-installed';

export interface PluginManifest {
  /** Plugin name */
  name: string;
  /** Plugin version */
  version: string;
  /** Plugin type */
  type: PluginType;
  /** Plugin description */
  description: string;
  /** Plugin author */
  author?: string;
  /** License */
  license?: string;
  /** Supported platforms */
  platforms: Array<'termux' | 'gnu-linux'>;
  /** Dependencies */
  dependencies?: Record<string, string>;
  /** Environment variables */
  env?: Record<string, {
    required: boolean;
    default?: string;
    description?: string;
  }>;
  /** Commands provided by plugin */
  commands?: Array<{
    name: string;
    description: string;
    handler: string;
  }>;
  /** Hooks */
  hooks?: {
    post_install?: string;
    pre_uninstall?: string;
    registered?: Array<{
      name: string;
      event: string;
      handler: string;
      priority: number;
      enabled: boolean;
      description?: string;
    }>;
  };
  /** MCP configuration */
  mcpConfig?: {
    defaultMode: string;
    localCommand?: string[];
    remoteUrl?: string;
    tools?: string[];
  };
  /** Features */
  features?: Record<string, unknown>;
}

export interface PluginInfo extends PluginManifest {
  /** Plugin directory path */
  path: string;
  /** Plugin status */
  status: PluginStatus;
  /** Main script path */
  main: string;
}

export interface PluginLoadOptions {
  /** Platform filter */
  platform?: 'termux' | 'gnu-linux';
  /** Type filter */
  type?: PluginType;
  /** Status filter */
  status?: PluginStatus;
}

export interface PluginRegistry {
  plugins: Map<string, PluginInfo>;
  loaded: Set<string>;
  enabled: Set<string>;
}
