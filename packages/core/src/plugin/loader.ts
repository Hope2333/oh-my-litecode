/**
 * Plugin Loader - OML Core
 * 
 * Loads and manages plugins (agents, subagents, MCPs, skills).
 */

import * as fs from 'fs';
import * as path from 'path';
import { exec } from 'child_process';
import type {
  Plugin,
  PluginType,
  PluginStatus,
  PluginInstallOptions,
  PluginCreateOptions,
  PluginRunOptions,
  PluginRunResult,
} from './types.js';

export interface PluginLoaderOptions {
  pluginsDir: string;
  configDir?: string;
}

export class PluginLoader {
  private pluginsDir: string;
  private configDir: string;
  private plugins: Map<string, Plugin>;
  private enabledPlugins: Set<string>;

  constructor(options: PluginLoaderOptions) {
    this.pluginsDir = options.pluginsDir;
    this.configDir = options.configDir || path.join(this.pluginsDir, '.config');
    this.plugins = new Map();
    this.enabledPlugins = new Set();
    this.ensureDirs();
  }

  private ensureDirs(): void {
    // Create plugin type directories
    const types: PluginType[] = ['agent', 'subagent', 'mcp', 'skill'];
    for (const type of types) {
      const dir = this.getPluginTypeDir(type);
      if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
      }
    }

    // Create config directory
    if (!fs.existsSync(this.configDir)) {
      fs.mkdirSync(this.configDir, { recursive: true });
    }

    // Load enabled plugins
    this.loadEnabledPlugins();
  }

  private getPluginTypeDir(type: PluginType): string {
    return path.join(this.pluginsDir, `${type}s`);
  }

  private loadEnabledPlugins(): void {
    const enabledFile = path.join(this.configDir, 'enabled.json');
    if (fs.existsSync(enabledFile)) {
      try {
        const data = JSON.parse(fs.readFileSync(enabledFile, 'utf-8'));
        for (const name of data.enabled || []) {
          this.enabledPlugins.add(name);
        }
      } catch (error) {
        // Ignore invalid enabled file
      }
    }
  }

  private saveEnabledPlugins(): void {
    const enabledFile = path.join(this.configDir, 'enabled.json');
    const data = {
      enabled: Array.from(this.enabledPlugins),
      updatedAt: new Date().toISOString(),
    };
    fs.writeFileSync(enabledFile, JSON.stringify(data, null, 2));
  }

  /**
   * List all plugins
   */
  async list(type?: PluginType): Promise<Plugin[]> {
    const plugins: Plugin[] = [];

    const types = type ? [type] : ['agent', 'subagent', 'mcp', 'skill'] as PluginType[];

    for (const pluginType of types) {
      const typeDir = this.getPluginTypeDir(pluginType);
      if (!fs.existsSync(typeDir)) {
        continue;
      }

      const entries = fs.readdirSync(typeDir, { withFileTypes: true });
      for (const entry of entries) {
        if (entry.isDirectory()) {
          const plugin = await this.loadPlugin(entry.name, pluginType);
          if (plugin) {
            plugins.push(plugin);
          }
        }
      }
    }

    return plugins;
  }

  /**
   * Load a single plugin
   */
  async loadPlugin(name: string, type?: PluginType): Promise<Plugin | null> {
    // Find plugin directory
    let pluginDir: string | null = null;

    if (type) {
      const dir = path.join(this.getPluginTypeDir(type), name);
      if (fs.existsSync(dir)) {
        pluginDir = dir;
      }
    } else {
      // Search all types
      for (const t of ['agent', 'subagent', 'mcp', 'skill'] as PluginType[]) {
        const dir = path.join(this.getPluginTypeDir(t), name);
        if (fs.existsSync(dir)) {
          pluginDir = dir;
          type = t;
          break;
        }
      }
    }

    if (!pluginDir || !type) {
      return null;
    }

    // Load plugin.json
    const metaFile = path.join(pluginDir, 'plugin.json');
    let meta: Partial<Plugin> = {};

    if (fs.existsSync(metaFile)) {
      try {
        meta = JSON.parse(fs.readFileSync(metaFile, 'utf-8'));
      } catch (error) {
        // Ignore invalid plugin.json
      }
    }

    // Find main script
    let mainScript: string | undefined;
    for (const script of ['main.sh', 'main.ts', 'main.js', 'index.sh', 'index.ts', 'index.js']) {
      if (fs.existsSync(path.join(pluginDir, script))) {
        mainScript = script;
        break;
      }
    }

    const plugin: Plugin = {
      name,
      type,
      version: meta.version || '0.0.0',
      description: meta.description || '',
      author: meta.author,
      status: this.enabledPlugins.has(name) ? 'enabled' : 'installed',
      path: pluginDir,
      mainScript,
      dependencies: meta.dependencies,
      config: meta.config,
      installedAt: this.getInstalledDate(pluginDir),
      enabledAt: this.enabledPlugins.has(name) ? this.getEnabledDate(name) : undefined,
    };

    return plugin;
  }

  private getInstalledDate(pluginDir: string): Date {
    try {
      const stat = fs.statSync(pluginDir);
      return stat.birthtime;
    } catch {
      return new Date();
    }
  }

  private getEnabledDate(name: string): Date | undefined {
    const enabledFile = path.join(this.configDir, 'enabled.json');
    if (fs.existsSync(enabledFile)) {
      try {
        const data = JSON.parse(fs.readFileSync(enabledFile, 'utf-8'));
        return data.updatedAt ? new Date(data.updatedAt) : undefined;
      } catch {
        return undefined;
      }
    }
    return undefined;
  }

  /**
   * Install a plugin
   */
  async install(options: PluginInstallOptions): Promise<Plugin> {
    const { source, type = 'agent', enable = false } = options;

    // Determine plugin name from source
    const name = path.basename(source);
    const targetDir = path.join(this.getPluginTypeDir(type), name);

    // Check if already installed
    if (fs.existsSync(targetDir)) {
      throw new Error(`Plugin already installed: ${name}`);
    }

    // Install from source
    if (source.startsWith('http://') || source.startsWith('https://')) {
      // Download from URL (simplified - in production would use proper git clone)
      throw new Error('URL installation not yet implemented');
    } else if (fs.existsSync(source)) {
      // Copy from local path
      fs.cpSync(source, targetDir, { recursive: true });
    } else {
      throw new Error(`Invalid source: ${source}`);
    }

    // Load the installed plugin
    const plugin = await this.loadPlugin(name, type);
    if (!plugin) {
      throw new Error('Failed to load installed plugin');
    }

    // Enable if requested
    if (enable) {
      await this.enable(name);
    }

    return plugin;
  }

  /**
   * Enable a plugin
   */
  async enable(name: string): Promise<void> {
    const plugin = await this.loadPlugin(name);
    if (!plugin) {
      throw new Error(`Plugin not found: ${name}`);
    }

    this.enabledPlugins.add(name);
    this.saveEnabledPlugins();
  }

  /**
   * Disable a plugin
   */
  async disable(name: string): Promise<void> {
    this.enabledPlugins.delete(name);
    this.saveEnabledPlugins();
  }

  /**
   * Run a plugin
   */
  async run(name: string, options?: PluginRunOptions): Promise<PluginRunResult> {
    const plugin = await this.loadPlugin(name);
    if (!plugin) {
      return {
        success: false,
        output: '',
        error: `Plugin not found: ${name}`,
        exitCode: 1,
      };
    }

    if (!plugin.mainScript) {
      return {
        success: false,
        output: '',
        error: `No main script found for plugin: ${name}`,
        exitCode: 1,
      };
    }

    const scriptPath = path.join(plugin.path, plugin.mainScript);
    const args = options?.args || [];
    const env = { ...process.env, ...(options?.env || {}) };

    return new Promise((resolve) => {
      const command = `${scriptPath} ${args.join(' ')}`;
      
      exec(command, { env, timeout: options?.timeout }, (error, stdout, stderr) => {
        if (error) {
          resolve({
            success: false,
            output: stdout,
            error: stderr || error.message,
            exitCode: 1,
          });
        } else {
          resolve({
            success: true,
            output: stdout,
            exitCode: 0,
          });
        }
      });
    });
  }

  /**
   * Get plugin info
   */
  async info(name: string): Promise<Plugin | null> {
    return this.loadPlugin(name);
  }

  /**
   * Create a new plugin template
   */
  async create(options: PluginCreateOptions): Promise<Plugin> {
    const { name, type, description = '', author = '' } = options;
    const pluginDir = path.join(this.getPluginTypeDir(type), name);

    // Check if already exists
    if (fs.existsSync(pluginDir)) {
      throw new Error(`Plugin already exists: ${name}`);
    }

    // Create plugin directory
    fs.mkdirSync(pluginDir, { recursive: true });

    // Create plugin.json
    const meta = {
      name,
      version: '0.1.0',
      description,
      author,
      type,
    };
    fs.writeFileSync(
      path.join(pluginDir, 'plugin.json'),
      JSON.stringify(meta, null, 2)
    );

    // Create main.sh template
    const mainScript = `#!/usr/bin/env bash
# ${name} - ${description}

set -euo pipefail

echo "${name} v0.1.0"
`;
    fs.writeFileSync(path.join(pluginDir, 'main.sh'), mainScript);
    fs.chmodSync(path.join(pluginDir, 'main.sh'), 0o755);

    // Create README.md
    const readme = `# ${name}

${description || 'A new OML plugin'}

## Usage

\`\`\`bash
oml plugin run ${name}
\`\`\`

## License

MIT
`;
    fs.writeFileSync(path.join(pluginDir, 'README.md'), readme);

    // Load and return the created plugin
    return (await this.loadPlugin(name, type))!;
  }

  /**
   * Uninstall a plugin
   */
  async uninstall(name: string): Promise<void> {
    const plugin = await this.loadPlugin(name);
    if (!plugin) {
      throw new Error(`Plugin not found: ${name}`);
    }

    // Disable first
    await this.disable(name);

    // Remove directory
    fs.rmSync(plugin.path, { recursive: true, force: true });
  }

  /**
   * Get enabled plugins
   */
  getEnabled(): string[] {
    return Array.from(this.enabledPlugins);
  }

  /**
   * Check if a plugin is enabled
   */
  isEnabled(name: string): boolean {
    return this.enabledPlugins.has(name);
  }
}
