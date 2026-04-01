#!/usr/bin/env node
/**
 * OML CLI Entry Point
 */

import { Command } from 'commander';
import { createQwenCommand } from '../commands/qwen.js';
import { createPluginCommand } from '../commands/plugin.js';
import { createCloudCommand } from '../commands/cloud.js';
import { createPerfCommand } from '../commands/perf.js';
import { createTuiCommand } from '../commands/tui.js';
import { HelpSystem } from '../ui/tree-menu.js';
import { info } from '@oml/core';

const program = new Command();

program
  .name('oml')
  .description('Oh-My-Litecode - Unified Toolchain Manager')
  .version('0.2.0');

// Add all commands
program.addCommand(createQwenCommand());
program.addCommand(createPluginCommand());
program.addCommand(createCloudCommand());
program.addCommand(createPerfCommand());
program.addCommand(createTuiCommand());

// Help command with tree menu
program
  .command('help [command]')
  .description('Show help')
  .action((command) => {
    const help = new HelpSystem();
    
    if (!command) {
      help.showMainHelp();
    } else {
      help.showCommandHelp(command);
    }
  });

// Default action
program.action(() => {
  info('OML ready. Use --help for available commands.');
  program.outputHelp();
});

program.parse();
