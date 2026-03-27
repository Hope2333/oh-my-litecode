/**
 * TUI Commands - OML CLI
 */

import { Command } from 'commander';
import { App, Box, Button, List, Menu, Input } from '@oml/modules/tui';
import { TerminalRenderer } from '@oml/modules/tui';

export function createTuiCommand(): Command {
  const tui = new Command('tui');

  tui
    .description('TUI interface commands')
    .hook('preAction', () => {
      // Initialize TUI
    });

  tui
    .command('start')
    .description('Start TUI interface')
    .option('-t, --theme <theme>', 'Color theme', 'default')
    .action(async (options) => {
      const renderer = new TerminalRenderer();
      const app = new App(renderer);
      
      // Create main menu
      const menu = new Menu(renderer, {
        x: 2,
        y: 2,
        title: 'OML SuperTUI',
        items: [
          { label: 'Session', shortcut: 'S', action: () => console.log('Session') },
          { label: 'Plugins', shortcut: 'P', action: () => console.log('Plugins') },
          { label: 'Settings', shortcut: 'C', action: () => console.log('Settings') },
          { label: 'Quit', shortcut: 'Q', action: () => app.stop() },
        ],
      });
      
      // Create info box
      const box = new Box(renderer, {
        x: 2,
        y: 5,
        width: 50,
        height: 10,
        title: 'Welcome',
        border: 'rounded',
      });
      
      app.add(menu);
      app.add(box);
      
      console.log('Starting OML SuperTUI...');
      console.log('Press Ctrl+C to exit');
      
      // For now, just show static screen
      app.render();
      console.log('Menu: Session [S] | Plugins [P] | Settings [C] | Quit [Q]');
    });

  tui
    .command('demo')
    .description('Show TUI demo')
    .action(async () => {
      const renderer = new TerminalRenderer();
      renderer.clear();
      
      // Draw demo screen
      const box = new Box(renderer, {
        x: 5,
        y: 3,
        width: 60,
        height: 15,
        title: 'OML TUI Demo',
        border: 'double',
      });
      
      box.render();
      renderer.drawText('Welcome to OML SuperTUI!', 10, 5, { fg: 'green', style: 'bold' });
      renderer.drawText('This is a demonstration of the TUI capabilities.', 10, 7);
      renderer.drawText('Press any key to exit...', 10, 15, { fg: 'yellow' });
      
      renderer.render();
      console.log('\nDemo complete!');
    });

  return tui;
}
