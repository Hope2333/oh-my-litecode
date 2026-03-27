/**
 * Plugin Commands - OML CLI
 */

import { Command } from 'commander';
import { PluginLoader } from '@oml/core/plugin';

export function createPluginCommand(): Command {
  const plugin = new Command('plugin');
  const loader = new PluginLoader({ pluginsDir: process.env.OML_PLUGINS_DIR || './plugins' });

  plugin
    .description('Plugin management commands')
    .hook('preAction', () => {
      // Initialize plugin loader
    });

  plugin
    .command('list')
    .description('List all plugins')
    .option('-t, --type <type>', 'Filter by plugin type')
    .action(async (options) => {
      const plugins = await loader.list(options.type);
      if (plugins.length === 0) {
        console.log('No plugins found');
        return;
      }
      console.log('Plugins:');
      for (const p of plugins) {
        console.log(`  ${p.name} (${p.type}) - ${p.version} - ${p.status}`);
      }
    });

  plugin
    .command('install <source>')
    .description('Install a plugin')
    .option('-t, --type <type>', 'Plugin type', 'agent')
    .option('-e, --enable', 'Enable after install')
    .action(async (source, options) => {
      try {
        const plugin = await loader.install({
          source,
          type: options.type,
          enable: options.enable,
        });
        console.log(`✓ Plugin installed: ${plugin.name}`);
      } catch (error: any) {
        console.error(`✗ Failed to install: ${error.message}`);
      }
    });

  plugin
    .command('uninstall <name>')
    .description('Uninstall a plugin')
    .action(async (name) => {
      try {
        await loader.uninstall(name);
        console.log(`✓ Plugin uninstalled: ${name}`);
      } catch (error: any) {
        console.error(`✗ Failed to uninstall: ${error.message}`);
      }
    });

  plugin
    .command('enable <name>')
    .description('Enable a plugin')
    .action(async (name) => {
      try {
        await loader.enable(name);
        console.log(`✓ Plugin enabled: ${name}`);
      } catch (error: any) {
        console.error(`✗ Failed to enable: ${error.message}`);
      }
    });

  plugin
    .command('disable <name>')
    .description('Disable a plugin')
    .action(async (name) => {
      try {
        await loader.disable(name);
        console.log(`✓ Plugin disabled: ${name}`);
      } catch (error: any) {
        console.error(`✗ Failed to disable: ${error.message}`);
      }
    });

  plugin
    .command('run <name> [args...]')
    .description('Run a plugin')
    .action(async (name, args) => {
      try {
        const result = await loader.run(name, { args });
        if (result.success) {
          console.log(result.output);
        } else {
          console.error(`✗ Failed: ${result.error}`);
        }
      } catch (error: any) {
        console.error(`✗ Failed to run: ${error.message}`);
      }
    });

  plugin
    .command('info <name>')
    .description('Show plugin information')
    .action(async (name) => {
      const info = await loader.info(name);
      if (!info) {
        console.error(`Plugin not found: ${name}`);
        return;
      }
      console.log(`Plugin: ${info.name}`);
      console.log(`  Type: ${info.type}`);
      console.log(`  Version: ${info.version}`);
      console.log(`  Status: ${info.status}`);
      console.log(`  Description: ${info.description}`);
    });

  return plugin;
}
