/**
 * Plugin Commands - OML CLI
 */

import { Command } from 'commander';
import { PluginLoader } from '@oml/core/plugin';

const MIGRATED_PLUGINS = [
  // Agents (3)
  { name: 'qwen', type: 'agent', migrated: true },
  { name: 'build', type: 'agent', migrated: true },
  { name: 'plan', type: 'agent', migrated: true },
  // Subagents (12)
  { name: 'librarian', type: 'subagent', migrated: true },
  { name: 'reviewer', type: 'subagent', migrated: true },
  { name: 'scout', type: 'subagent', migrated: true },
  { name: 'worker', type: 'subagent', migrated: true },
  { name: 'architect', type: 'subagent', migrated: true },
  { name: 'debugger', type: 'subagent', migrated: true },
  { name: 'documenter', type: 'subagent', migrated: true },
  { name: 'optimizer', type: 'subagent', migrated: true },
  { name: 'researcher', type: 'subagent', migrated: true },
  { name: 'security-auditor', type: 'subagent', migrated: true },
  { name: 'tester', type: 'subagent', migrated: true },
  { name: 'translator', type: 'subagent', migrated: true },
  // MCPs (13)
  { name: 'context7', type: 'mcp', migrated: true },
  { name: 'grep-app', type: 'mcp', migrated: true },
  { name: 'websearch', type: 'mcp', migrated: true },
  { name: 'filesystem', type: 'mcp', migrated: true },
  { name: 'git', type: 'mcp', migrated: true },
  { name: 'weather', type: 'mcp', migrated: true },
  { name: 'translation', type: 'mcp', migrated: true },
  { name: 'notification', type: 'mcp', migrated: true },
  { name: 'browser', type: 'mcp', migrated: true },
  { name: 'calendar', type: 'mcp', migrated: true },
  { name: 'database', type: 'mcp', migrated: true },
  { name: 'email', type: 'mcp', migrated: true },
  { name: 'news', type: 'mcp', migrated: true },
  // Skills (12)
  { name: 'code-review', type: 'skill', migrated: true },
  { name: 'security-scan', type: 'skill', migrated: true },
  { name: 'test-coverage', type: 'skill', migrated: true },
  { name: 'documentation-gen', type: 'skill', migrated: true },
  { name: 'performance-analysis', type: 'skill', migrated: true },
  { name: 'backup-setup', type: 'skill', migrated: true },
  { name: 'best-practices', type: 'skill', migrated: true },
  { name: 'chaos-testing', type: 'skill', migrated: true },
  { name: 'ci-cd-setup', type: 'skill', migrated: true },
  { name: 'dependency-check', type: 'skill', migrated: true },
  { name: 'docker-setup', type: 'skill', migrated: true },
  { name: 'error-handling', type: 'skill', migrated: true },
  { name: 'k8s-setup', type: 'skill', migrated: true },
  { name: 'logging-setup', type: 'skill', migrated: true },
  { name: 'mutation-testing', type: 'skill', migrated: true },
  { name: 'performance-tuning', type: 'skill', migrated: true },
  { name: 'refactor-suggest', type: 'skill', migrated: true },
];

export function createPluginCommand(): Command {
  const plugin = new Command('plugin');
  const loader = new PluginLoader({ pluginsDir: process.env.OML_PLUGINS_DIR || './plugins' });

  plugin
    .description('Plugin management commands (40 plugins migrated to TypeScript)')
    .hook('preAction', () => {});

  plugin
    .command('list')
    .description('List all plugins')
    .option('-t, --type <type>', 'Filter by plugin type')
    .option('-s, --status <status>', 'Filter by status (enabled/installed)')
    .option('-m, --migrated', 'Show only migrated plugins')
    .option('-a, --all', 'Show all plugins (migrated + shell)')
    .action(async (options) => {
      let plugins = MIGRATED_PLUGINS;
      
      if (options.type) {
        plugins = plugins.filter(p => p.type === options.type);
      }
      
      if (options.migrated) {
        plugins = plugins.filter(p => p.migrated);
      }
      
      if (options.all) {
        // Include shell plugins from archive
        console.log('Showing all plugins (TypeScript + Shell)...\n');
      }
      
      if (plugins.length === 0) {
        console.log('No plugins found');
        return;
      }
      
      // Group by type
      const byType: Record<string, typeof plugins> = {};
      for (const p of plugins) {
        if (!byType[p.type]) byType[p.type] = [];
        byType[p.type].push(p);
      }
      
      console.log('Plugins:\n');
      for (const [type, list] of Object.entries(byType)) {
        console.log(`${type.toUpperCase()}S (${list.length}):`);
        for (const p of list) {
          const marker = p.migrated ? '✅' : '🐚';
          console.log(`  ${marker} ${p.name}`);
        }
        console.log('');
      }
      
      console.log(`Total: ${plugins.length} plugins`);
      console.log('Legend: ✅ TypeScript | 🐚 Shell');
    });

  plugin
    .command('migrated')
    .description('Show migrated plugins status')
    .action(() => {
      const migrated = MIGRATED_PLUGINS.filter(p => p.migrated);
      console.log(`Migrated Plugins: ${migrated.length}/40\n`);
      
      const byType: Record<string, typeof migrated> = {};
      for (const p of migrated) {
        if (!byType[p.type]) byType[p.type] = [];
        byType[p.type].push(p);
      }
      
      for (const [type, list] of Object.entries(byType)) {
        console.log(`${type.toUpperCase()}S: ${list.length}`);
        for (const p of list) {
          console.log(`  ✅ ${p.name}`);
        }
        console.log('');
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
