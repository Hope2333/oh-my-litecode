/**
 * OML Plugin Loader
 * 
 * TypeScript implementation of plugin loading and management
 * Replaces: core/plugin-loader.sh
 */

import * as fs from 'fs';
import * as path from 'path';
import type { 
  PluginManifest, 
  PluginInfo, 
  PluginType, 
  PluginStatus,
  PluginLoadOptions,
  PluginRegistry 
} from './plugin-loader.types';

/**
 * Get OML root directory
 */
export function getOmlRoot(): string {
  // Check environment variable first
  if (process.env.OML_ROOT) {
    return process.env.OML_ROOT;
  }
  
  // Default to ../ from src/core
  const defaultPath = path.resolve(__dirname, '../../');
  if (fs.existsSync(path.join(defaultPath, 'oml'))) {
    return defaultPath;
  }
  
  // Fallback to current directory
  return process.cwd();
}

/**
 * Get plugins directory
 */
export function getPluginsDir(): string {
  return path.join(getOmlRoot(), 'plugins');
}

/**
 * Find plugin directory by name
 */
export function findPluginDir(name: string, type?: PluginType): string | null {
  const pluginsDir = getPluginsDir();
  
  if (!fs.existsSync(pluginsDir)) {
    return null;
  }
  
  // If type specified, search in type directory
  if (type) {
    const typeDir = path.join(pluginsDir, type + 's');
    const pluginPath = path.join(typeDir, name);
    if (fs.existsSync(pluginPath)) {
      return pluginPath;
    }
  }
  
  // Search all plugin types
  const pluginTypes: PluginType[] = ['agent', 'subagent', 'mcp', 'skill', 'core'];
  for (const pluginType of pluginTypes) {
    const typeDir = path.join(pluginsDir, pluginType + 's');
    if (!fs.existsSync(typeDir)) continue;
    
    const pluginPath = path.join(typeDir, name);
    if (fs.existsSync(pluginPath)) {
      return pluginPath;
    }
  }
  
  return null;
}

/**
 * Load plugin manifest
 */
export function loadPluginManifest(pluginDir: string): PluginManifest | null {
  const manifestPath = path.join(pluginDir, 'plugin.json');
  
  if (!fs.existsSync(manifestPath)) {
    return null;
  }
  
  try {
    const content = fs.readFileSync(manifestPath, 'utf-8');
    return JSON.parse(content) as PluginManifest;
  } catch (error) {
    console.error(`Failed to load plugin manifest: ${manifestPath}`);
    console.error(error);
    return null;
  }
}

/**
 * Get plugin status
 */
export function getPluginStatus(pluginDir: string, manifest: PluginManifest): PluginStatus {
  // Check if main script exists
  const mainScript = path.join(pluginDir, 'main.sh');
  if (!fs.existsSync(mainScript)) {
    return 'not-installed';
  }
  
  // Check if enabled (simplified - would need actual state tracking)
  return 'enabled';
}

/**
 * Load single plugin
 */
export function loadPlugin(name: string, type?: PluginType): PluginInfo | null {
  const pluginDir = findPluginDir(name, type);
  
  if (!pluginDir) {
    return null;
  }
  
  const manifest = loadPluginManifest(pluginDir);
  
  if (!manifest) {
    return null;
  }
  
  const status = getPluginStatus(pluginDir, manifest);
  const mainScript = path.join(pluginDir, 'main.sh');
  
  return {
    ...manifest,
    path: pluginDir,
    status,
    main: mainScript,
  };
}

/**
 * List all plugins
 */
export function listPlugins(options?: PluginLoadOptions): PluginInfo[] {
  const plugins: PluginInfo[] = [];
  const pluginsDir = getPluginsDir();
  
  if (!fs.existsSync(pluginsDir)) {
    return plugins;
  }
  
  const pluginTypes: PluginType[] = ['agent', 'subagent', 'mcp', 'skill', 'core'];
  
  for (const pluginType of pluginTypes) {
    // Apply type filter
    if (options?.type && pluginType !== options.type) {
      continue;
    }
    
    const typeDir = path.join(pluginsDir, pluginType + 's');
    if (!fs.existsSync(typeDir)) continue;
    
    const entries = fs.readdirSync(typeDir, { withFileTypes: true });
    
    for (const entry of entries) {
      if (!entry.isDirectory()) continue;
      
      const pluginDir = path.join(typeDir, entry.name);
      const manifest = loadPluginManifest(pluginDir);
      
      if (!manifest) continue;
      
      // Apply platform filter
      if (options?.platform && !manifest.platforms.includes(options.platform)) {
        continue;
      }
      
      const status = getPluginStatus(pluginDir, manifest);
      
      // Apply status filter
      if (options?.status && status !== options.status) {
        continue;
      }
      
      plugins.push({
        ...manifest,
        path: pluginDir,
        status,
        main: path.join(pluginDir, 'main.sh'),
      });
    }
  }
  
  return plugins;
}

/**
 * Get plugin information
 */
export function getPluginInfo(name: string, type?: PluginType): PluginInfo | null {
  return loadPlugin(name, type);
}

/**
 * Check if plugin is installed
 */
export function isPluginInstalled(name: string, type?: PluginType): boolean {
  const plugin = loadPlugin(name, type);
  return plugin !== null && plugin.status !== 'not-installed';
}

/**
 * Check if plugin is enabled
 */
export function isPluginEnabled(name: string, type?: PluginType): boolean {
  const plugin = loadPlugin(name, type);
  return plugin !== null && plugin.status === 'enabled';
}

/**
 * Enable plugin
 */
export async function enablePlugin(name: string, type?: PluginType): Promise<boolean> {
  const plugin = loadPlugin(name, type);
  
  if (!plugin) {
    console.error(`Plugin not found: ${name}`);
    return false;
  }
  
  // Run post-install hook if exists
  const postInstall = path.join(plugin.path, 'scripts', 'post-install.sh');
  if (fs.existsSync(postInstall)) {
    try {
      const { execSync } = await import('child_process');
      execSync(`bash "${postInstall}"`, { stdio: 'inherit' });
    } catch (error) {
      console.error(`Failed to run post-install hook: ${postInstall}`);
      console.error(error);
      return false;
    }
  }
  
  return true;
}

/**
 * Disable plugin
 */
export async function disablePlugin(name: string, type?: PluginType): Promise<boolean> {
  const plugin = loadPlugin(name, type);
  
  if (!plugin) {
    console.error(`Plugin not found: ${name}`);
    return false;
  }
  
  // Run pre-uninstall hook if exists
  const preUninstall = path.join(plugin.path, 'scripts', 'pre-uninstall.sh');
  if (fs.existsSync(preUninstall)) {
    try {
      const { execSync } = await import('child_process');
      execSync(`bash "${preUninstall}"`, { stdio: 'inherit' });
    } catch (error) {
      console.error(`Failed to run pre-uninstall hook: ${preUninstall}`);
      console.error(error);
      return false;
    }
  }
  
  return true;
}

// CLI export
if (import.meta.url === `file://${process.argv[1]}`) {
  const action = process.argv[2] || 'list';
  
  if (action === 'list') {
    const plugins = listPlugins();
    console.log(`Loaded ${plugins.length} plugin(s):\n`);
    for (const plugin of plugins) {
      console.log(`${plugin.name}:${plugin.version}`);
    }
  } else if (action === 'info' && process.argv[3]) {
    const name = process.argv[3];
    const plugin = getPluginInfo(name);
    if (plugin) {
      console.log(`Plugin: ${plugin.name}`);
      console.log(`Version: ${plugin.version}`);
      console.log(`Type: ${plugin.type}`);
      console.log(`Status: ${plugin.status}`);
      console.log(`Path: ${plugin.path}`);
      console.log(`Description: ${plugin.description}`);
    } else {
      console.error(`Plugin not found: ${name}`);
      process.exit(1);
    }
  }
}
