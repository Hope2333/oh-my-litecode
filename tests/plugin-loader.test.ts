import { describe, it, expect } from 'vitest';
import { 
  listPlugins,
  getPluginInfo,
  isPluginInstalled,
  getOmlRoot,
  getPluginsDir
} from '../src/core/plugin-loader.js';

describe('Plugin Loader', () => {
  it('should get OML root', () => {
    const root = getOmlRoot();
    expect(root).toBeDefined();
    expect(root).toContain('oh-my-litecode');
  });

  it('should get plugins directory', () => {
    const pluginsDir = getPluginsDir();
    expect(pluginsDir).toBeDefined();
  });

  it('should list plugins', () => {
    const plugins = listPlugins();
    expect(plugins.length).toBeGreaterThan(0);
  });

  it('should list qwen plugin', () => {
    const plugins = listPlugins();
    const qwenPlugin = plugins.find(p => p.name === 'qwen');
    expect(qwenPlugin).toBeDefined();
    expect(qwenPlugin?.type).toBe('agent');
  });

  it('should get plugin info', () => {
    const plugin = getPluginInfo('qwen');
    expect(plugin).toBeDefined();
    expect(plugin?.name).toBe('qwen');
    expect(plugin?.type).toBe('agent');
  });

  it('should check if plugin is installed', () => {
    const installed = isPluginInstalled('qwen');
    expect(installed).toBe(true);
  });

  it('should return false for non-existent plugin', () => {
    const plugin = getPluginInfo('non-existent-plugin-xyz');
    expect(plugin).toBeNull();
  });
});
