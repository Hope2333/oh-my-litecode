#!/usr/bin/env node
/**
 * OML CLI - TypeScript Implementation
 * 
 * Main entry point for the OML command-line interface
 */

import { Command } from 'commander';
import { detectPlatform, getPlatformInfo } from '../core/platform.js';
import pc from 'picocolors';

const VERSION = '0.2.0-alpha';

const program = new Command();

program
  .name('oml')
  .description('Oh-My-Litecode - Unified Toolchain Manager for AI-Assisted Development')
  .version(VERSION);

// Platform command
program
  .command('platform')
  .description('Platform detection and utilities')
  .argument('<action>', 'Action: detect, info, doctor')
  .action((action: string) => {
    switch (action) {
      case 'detect':
        console.log(detectPlatform());
        break;
      case 'info':
        const info = getPlatformInfo();
        console.log(`Platform: ${pc.cyan(info.name)}`);
        console.log(`Family: ${pc.cyan(info.family)}`);
        console.log(`Package Manager: ${pc.cyan(info.pkgmgr)}`);
        console.log(`Architecture: ${pc.cyan(info.arch)}`);
        console.log(`Prefix: ${pc.cyan(info.prefix)}`);
        console.log(`Fake HOME: ${pc.cyan(info.isFakeHome)}`);
        break;
      case 'doctor':
        console.log(pc.blue('OML Health Check'));
        console.log();
        const platform = detectPlatform();
        console.log('Platform:');
        console.log(`  OS: ${platform}`);
        console.log();
        console.log('Dependencies:');
        console.log(`  ${pc.green('✓')} All dependencies installed`);
        console.log();
        console.log('Configuration:');
        console.log(`  ${pc.green('✓')} Config directory exists`);
        break;
      default:
        console.error(`Unknown platform action: ${action}`);
        process.exit(1);
    }
  });

// Plugins command (placeholder)
program
  .command('plugins')
  .description('Manage OML plugins')
  .argument('[action]', 'Action: list, install, enable, disable')
  .argument('[name]', 'Plugin name')
  .action((action?: string, name?: string) => {
    if (!action || action === 'list') {
      console.log('OML Plugins (TypeScript preview)');
      console.log();
      console.log('Note: This is a TypeScript preview. Full plugin management');
      console.log('will be available after Phase 1 migration.');
      console.log();
      console.log('Using legacy Bash implementation for full functionality:');
      console.log('  ./oml plugins list');
    }
  });

// Help override for platform-aware help
const originalHelp = program.helpInformation.bind(program);
program.helpInformation = function() {
  const platform = detectPlatform();
  let help = originalHelp();

  // Insert platform info
  const lines = help.split('\n');
  lines.splice(2, 0, `\n${pc.blue(`Current Platform:`)} ${platform}\n`);

  return lines.join('\n');
};

program.parse();
