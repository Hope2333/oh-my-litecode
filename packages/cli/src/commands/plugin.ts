/**
 * Plugin Commands - OML CLI
 * 
 * Plugin management commands for OML.
 * Supports all 20 migrated TypeScript plugins:
 * - Agents (3): qwen, build, plan
 * - Subagents (4): librarian, reviewer, scout, worker
 * - MCPs (8): context7, grep-app, websearch, filesystem, git, weather, translation, notification
 * - Skills (5): code-review, security-scan, test-coverage, documentation-gen, performance-analysis
 */

import { Command } from 'commander';
import { PluginLoader } from '@oml/core/plugin';
import type { Plugin, PluginType } from '@oml/core/plugin';

// The 20 migrated TypeScript plugins
const MIGRATED_PLUGINS = {
  agents: ['qwen', 'build', 'plan'],
  subagents: ['librarian', 'reviewer', 'scout', 'worker'],
  mcps: ['context7', 'grep-app', 'websearch', 'filesystem', 'git', 'weather', 'translation', 'notification'],
  skills: ['code-review', 'security-scan', 'test-coverage', 'documentation-gen', 'performance-analysis'],
};

export function createPluginCommand(): Command {
  const plugin = new Command('plugin');
  
  // Use default plugins directory or environment variable
  const pluginsDir = process.env.OML_PLUGINS_DIR || 
    process.env.HOME + '/.local/home/qwenx/.oml/plugins';
  const loader = new PluginLoader({ pluginsDir });

  plugin
    .description('Plugin management commands')
    .hook('preAction', async () => {
      // Initialize plugin loader
    });

  plugin
    .command('list')
    .description('List all plugins')
    .option('-t, --type <type>', 'Filter by plugin type (agent|subagent|mcp|skill)')
    .option('-s, --status <status>', 'Filter by status (enabled|disabled|installed)')
    .option('--migrated', 'Show only migrated TypeScript plugins')
    .action(async (options) => {
      const typeFilter = options.type as PluginType | undefined;
      const statusFilter = options.status;
      const migratedOnly = options.migrated;

      const plugins = await loader.list(typeFilter);
      
      let filtered = plugins;
      
      if (statusFilter) {
        filtered = filtered.filter(p => p.status === statusFilter);
      }
      
      if (migratedOnly) {
        const allMigrated = [
          ...MIGRATED_PLUGINS.agents,
          ...MIGRATED_PLUGINS.subagents,
          ...MIGRATED_PLUGINS.mcps,
          ...MIGRATED_PLUGINS.skills,
        ];
        filtered = filtered.filter(p => allMigrated.includes(p.name));
      }

      if (filtered.length === 0) {
        console.log('No plugins found');
        return;
      }

      // Group by type for better display
      const grouped = groupByType(filtered);
      
      console.log('');
      console.log(formatHeader('OML Plugins'));
      console.log('');
      
      for (const [type, typePlugins] of Object.entries(grouped)) {
        console.log(formatTypeHeader(type));
        for (const p of typePlugins) {
          console.log(formatPluginRow(p));
        }
        console.log('');
      }
      
      console.log(formatSummary(filtered.length));
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
        console.log(formatSuccess(`Plugin installed: ${plugin.name} v${plugin.version}`));
      } catch (error: any) {
        console.error(formatError(`Failed to install: ${error.message}`));
      }
    });

  plugin
    .command('uninstall <name>')
    .description('Uninstall a plugin')
    .option('-f, --force', 'Force uninstall without confirmation')
    .action(async (name, options) => {
      try {
        if (!options.force) {
          console.log(`Uninstalling plugin: ${name}`);
        }
        await loader.uninstall(name);
        console.log(formatSuccess(`Plugin uninstalled: ${name}`));
      } catch (error: any) {
        console.error(formatError(`Failed to uninstall: ${error.message}`));
      }
    });

  plugin
    .command('enable <name>')
    .description('Enable a plugin')
    .action(async (name) => {
      try {
        await loader.enable(name);
        console.log(formatSuccess(`Plugin enabled: ${name}`));
      } catch (error: any) {
        console.error(formatError(`Failed to enable: ${error.message}`));
      }
    });

  plugin
    .command('disable <name>')
    .description('Disable a plugin')
    .action(async (name) => {
      try {
        await loader.disable(name);
        console.log(formatSuccess(`Plugin disabled: ${name}`));
      } catch (error: any) {
        console.error(formatError(`Failed to disable: ${error.message}`));
      }
    });

  plugin
    .command('run <name> [args...]')
    .description('Run a plugin')
    .option('--timeout <ms>', 'Timeout in milliseconds', '30000')
    .action(async (name, args, options) => {
      try {
        const result = await loader.run(name, { 
          args,
          timeout: parseInt(options.timeout, 10),
        });
        if (result.success) {
          if (result.output) {
            console.log(result.output);
          } else {
            console.log(formatSuccess(`Plugin ${name} executed successfully`));
          }
        } else {
          console.error(formatError(`Failed: ${result.error}`));
          process.exit(1);
        }
      } catch (error: any) {
        console.error(formatError(`Failed to run: ${error.message}`));
        process.exit(1);
      }
    });

  plugin
    .command('info <name>')
    .description('Show detailed plugin information')
    .action(async (name) => {
      const info = await loader.info(name);
      if (!info) {
        console.error(formatError(`Plugin not found: ${name}`));
        return;
      }
      
      console.log('');
      console.log(formatHeader(`Plugin: ${info.name}`));
      console.log('');
      console.log(formatInfoField('Name', info.name));
      console.log(formatInfoField('Type', info.type));
      console.log(formatInfoField('Version', info.version));
      console.log(formatInfoField('Status', formatStatus(info.status)));
      console.log(formatInfoField('Description', info.description || 'N/A'));
      
      if (info.author) {
        console.log(formatInfoField('Author', info.author));
      }
      
      if (info.mainScript) {
        console.log(formatInfoField('Main Script', `${info.mainScript}${info.scriptType ? ` (${info.scriptType})` : ''}`));
      }
      
      if (info.dependencies && info.dependencies.length > 0) {
        console.log(formatInfoField('Dependencies', info.dependencies.join(', ')));
      }
      
      console.log(formatInfoField('Path', info.path));
      console.log(formatInfoField('Installed', info.installedAt.toLocaleDateString()));
      
      if (info.enabledAt) {
        console.log(formatInfoField('Enabled', info.enabledAt.toLocaleDateString()));
      }
      
      // Show migrated status
      const allMigrated = [
        ...MIGRATED_PLUGINS.agents,
        ...MIGRATED_PLUGINS.subagents,
        ...MIGRATED_PLUGINS.mcps,
        ...MIGRATED_PLUGINS.skills,
      ];
      if (allMigrated.includes(info.name)) {
        console.log('');
        console.log(formatNote('This is a migrated TypeScript plugin'));
      }
      
      console.log('');
    });

  // Add a command to show migrated plugins status
  plugin
    .command('migrated')
    .description('Show status of migrated TypeScript plugins')
    .action(async () => {
      const allPlugins = await loader.list();
      const pluginMap = new Map(allPlugins.map(p => [p.name, p]));
      
      console.log('');
      console.log(formatHeader('Migrated TypeScript Plugins'));
      console.log('');
      
      let total = 0;
      let enabled = 0;
      
      for (const [type, names] of Object.entries(MIGRATED_PLUGINS)) {
        console.log(formatTypeHeader(type));
        for (const name of names) {
          const p = pluginMap.get(name);
          total++;
          if (p) {
            if (p.status === 'enabled') enabled++;
            console.log(formatPluginRow(p));
          } else {
            console.log(formatMissingPlugin(name));
          }
        }
        console.log('');
      }
      
      console.log(formatMigrationSummary(total, enabled));
    });

  return plugin;
}

/**
 * Group plugins by type
 */
function groupByType(plugins: Plugin[]): Record<string, Plugin[]> {
  const grouped: Record<string, Plugin[]> = {};
  for (const p of plugins) {
    if (!grouped[p.type]) {
      grouped[p.type] = [];
    }
    grouped[p.type].push(p);
  }
  return grouped;
}

/**
 * Format output with colors (simplified for now)
 */
function formatHeader(text: string): string {
  return `═══ ${text} ═══`;
}

function formatTypeHeader(type: string): string {
  const typeLabels: Record<string, string> = {
    agent: 'Agents',
    subagent: 'Subagents',
    mcp: 'MCPs',
    skill: 'Skills',
  };
  return `┌─ ${typeLabels[type] || type} ──────────────────────────────────`;
}

function formatPluginRow(p: Plugin): string {
  const statusIcon = p.status === 'enabled' ? '✓' : p.status === 'installed' ? '○' : '○';
  const scriptType = p.scriptType ? ` [${p.scriptType}]` : '';
  return `│ ${statusIcon} ${p.name.padEnd(25)} v${p.version.padEnd(10)} ${p.status.padEnd(10)}${scriptType}`;
}

function formatMissingPlugin(name: string): string {
  return `│ ○ ${name.padEnd(25)} (not installed)`;
}

function formatSummary(count: number): string {
  return `└─ Total: ${count} plugin${count !== 1 ? 's' : ''}`;
}

function formatMigrationSummary(total: number, enabled: number): string {
  return `└─ Migrated: ${total}/20 plugins, ${enabled} enabled`;
}

function formatSuccess(text: string): string {
  return `✓ ${text}`;
}

function formatError(text: string): string {
  return `✗ ${text}`;
}

function formatInfoField(label: string, value: string): string {
  return `  ${label.padEnd(15)}: ${value}`;
}

function formatStatus(status: string): string {
  const statusLabels: Record<string, string> = {
    enabled: 'Enabled ✓',
    disabled: 'Disabled ○',
    installed: 'Installed ○',
  };
  return statusLabels[status] || status;
}

function formatNote(text: string): string {
  return `  ℹ ${text}`;
}
