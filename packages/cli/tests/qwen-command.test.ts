import { describe, expect, it } from 'vitest';
import { createQwenCommand } from '../src/commands/qwen.js';

describe('createQwenCommand', () => {
  it('registers the expected top-level subcommands', () => {
    const command = createQwenCommand();
    const names = command.commands.map((subcommand) => subcommand.name());

    expect(command.name()).toBe('qwen');
    expect(names).toEqual(['chat', 'session', 'config', 'keys', 'mcp', 'help']);
  });

  it('registers session management actions', () => {
    const command = createQwenCommand();
    const session = command.commands.find((subcommand) => subcommand.name() === 'session');
    const sessionNames = session?.commands.map((subcommand) => subcommand.name());

    expect(sessionNames).toEqual(['list', 'show', 'switch', 'create', 'delete']);
  });
});
