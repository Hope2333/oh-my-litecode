/**
 * OML CLI
 */

import { Command } from 'commander';
import { createPluginCommand } from './commands/plugin.js';
import { createCloudCommand } from './commands/cloud.js';
import { createPerfCommand } from './commands/perf.js';
import { createTuiCommand } from './commands/tui.js';
import { createQwenCommand } from './commands/qwen.js';

export function createCLI(): Command {
  const cli = new Command();

  cli
    .name('oml')
    .description('Oh-My-Litecode - Unified Toolchain Manager')
    .version('0.3.0');

  cli.addCommand(createQwenCommand());
  cli.addCommand(createPluginCommand());
  cli.addCommand(createCloudCommand());
  cli.addCommand(createPerfCommand());
  cli.addCommand(createTuiCommand());

  return cli;
}

if (require.main === module) {
  const cli = createCLI();
  cli.parse();
}
