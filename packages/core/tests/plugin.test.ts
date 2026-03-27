import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'fs';
import * as path from 'path';
import { PluginLoader } from '../src/plugin/loader.js';

describe('PluginLoader', () => {
  let testDir: string;
  let loader: PluginLoader;

  beforeEach(() => {
    testDir = path.join(process.cwd(), 'test-plugins-' + Date.now());
    fs.mkdirSync(testDir, { recursive: true });
    
    loader = new PluginLoader({ pluginsDir: testDir });
  });

  afterEach(() => {
    fs.rmSync(testDir, { recursive: true, force: true });
  });

  it('should initialize with empty plugin list', async () => {
    const plugins = await loader.list();
    expect(plugins.length).toBe(0);
  });

  it('should create a new plugin', async () => {
    const plugin = await loader.create({
      name: 'test-plugin',
      type: 'agent',
      description: 'A test plugin',
    });

    expect(plugin.name).toBe('test-plugin');
    expect(plugin.type).toBe('agent');
    expect(plugin.status).toBe('installed');
    expect(fs.existsSync(plugin.path)).toBe(true);
    expect(fs.existsSync(path.join(plugin.path, 'plugin.json'))).toBe(true);
    expect(fs.existsSync(path.join(plugin.path, 'main.sh'))).toBe(true);
  });

  it('should enable a plugin', async () => {
    const plugin = await loader.create({
      name: 'test-plugin',
      type: 'agent',
    });

    await loader.enable('test-plugin');

    expect(loader.isEnabled('test-plugin')).toBe(true);
    
    const updated = await loader.info('test-plugin');
    expect(updated?.status).toBe('enabled');
  });

  it('should disable a plugin', async () => {
    const plugin = await loader.create({
      name: 'test-plugin',
      type: 'agent',
    });

    await loader.enable('test-plugin');
    await loader.disable('test-plugin');

    expect(loader.isEnabled('test-plugin')).toBe(false);
  });

  it('should list plugins by type', async () => {
    await loader.create({ name: 'agent-1', type: 'agent' });
    await loader.create({ name: 'agent-2', type: 'agent' });
    await loader.create({ name: 'mcp-1', type: 'mcp' });

    const allPlugins = await loader.list();
    expect(allPlugins.length).toBe(3);

    const agentPlugins = await loader.list('agent');
    expect(agentPlugins.length).toBe(2);

    const mcpPlugins = await loader.list('mcp');
    expect(mcpPlugins.length).toBe(1);
  });

  it('should install a plugin from local path', async () => {
    // Create a source plugin
    const sourceDir = path.join(testDir, 'source-plugin');
    fs.mkdirSync(sourceDir, { recursive: true });
    fs.writeFileSync(
      path.join(sourceDir, 'plugin.json'),
      JSON.stringify({ name: 'source-plugin', version: '1.0.0' })
    );
    fs.writeFileSync(path.join(sourceDir, 'main.sh'), '#!/bin/bash\necho test');

    // Install from source
    const plugin = await loader.install({
      source: sourceDir,
      type: 'agent',
      enable: true,
    });

    expect(plugin.name).toBe('source-plugin');
    expect(loader.isEnabled('source-plugin')).toBe(true);
  });

  it('should throw when installing duplicate plugin', async () => {
    await loader.create({ name: 'duplicate', type: 'agent' });

    const sourceDir = path.join(testDir, 'duplicate');
    fs.mkdirSync(sourceDir, { recursive: true });

    await expect(loader.install({ source: sourceDir, type: 'agent' })).rejects.toThrow('already installed');
  });

  it('should uninstall a plugin', async () => {
    const plugin = await loader.create({
      name: 'test-plugin',
      type: 'agent',
    });

    await loader.uninstall('test-plugin');

    const plugins = await loader.list();
    expect(plugins.length).toBe(0);
    expect(fs.existsSync(plugin.path)).toBe(false);
  });

  it('should run a plugin', async () => {
    const plugin = await loader.create({
      name: 'test-plugin',
      type: 'agent',
      description: 'A test plugin',
    });

    const result = await loader.run('test-plugin');

    expect(result.success).toBe(true);
    expect(result.output).toContain('test-plugin v0.1.0');
    expect(result.exitCode).toBe(0);
  });

  it('should get plugin info', async () => {
    const plugin = await loader.create({
      name: 'test-plugin',
      type: 'agent',
      description: 'A test plugin',
    });

    const info = await loader.info('test-plugin');

    expect(info).toBeDefined();
    expect(info?.name).toBe('test-plugin');
    expect(info?.type).toBe('agent');
  });

  it('should return null for non-existent plugin', async () => {
    const info = await loader.info('non-existent');
    expect(info).toBeNull();
  });

  it('should persist enabled plugins', async () => {
    await loader.create({ name: 'plugin-1', type: 'agent' });
    await loader.create({ name: 'plugin-2', type: 'agent' });

    await loader.enable('plugin-1');
    await loader.enable('plugin-2');

    // Create new loader instance
    const loader2 = new PluginLoader({ pluginsDir: testDir });
    
    expect(loader2.isEnabled('plugin-1')).toBe(true);
    expect(loader2.isEnabled('plugin-2')).toBe(true);
  });
});
