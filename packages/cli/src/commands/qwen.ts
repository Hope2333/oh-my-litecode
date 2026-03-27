/**
 * Qwen Command - OML CLI
 * 
 * Qwen controller command.
 */

import { Command } from 'commander';
import { 
  SessionManager, 
  HooksEngine, 
  registerHook,
  triggerHook,
  Logger,
  info,
  error 
} from '@oml/core';

const logger = new Logger({ name: 'oml:qwen', level: 'info' });

export function createQwenCommand(): Command {
  const qwen = new Command('qwen');
  
  qwen
    .description('Qwen agent controller')
    .action(() => {
      info('Qwen controller ready. Use subcommands for specific actions.');
    });

  // Chat subcommand - IMPLEMENTED
  qwen
    .command('chat')
    .description('Start chat session with Qwen')
    .argument('[query]', 'Query to send to Qwen')
    .option('-s, --session <id>', 'Session ID to use or create')
    .option('-m, --model <name>', 'Model name (default: qwen-plus)')
    .option('-t, --temperature <number>', 'Temperature for generation', '0.7')
    .option('--max-tokens <number>', 'Max tokens in response', '2048')
    .action(async (query, options) => {
      const { SessionManager } = await import('@oml/core');
      const { OAuthSwitcher } = await import('@oml/modules/switchers');
      
      logger.info(`Starting chat: ${query || 'interactive mode'}`);
      
      const manager = new SessionManager({ sessionsDir: './sessions' });
      const sessionId = options.session || `chat-${Date.now()}`;
      
      let session = await manager.resume(sessionId);
      if (!session) {
        session = await manager.create({ name: sessionId });
        logger.info(`Created new session: ${sessionId}`);
      }
      
      const switcher = new OAuthSwitcher();
      const apiKey = process.env.QWEN_API_KEY || switcher.getCurrent()?.accessToken;
      
      if (!apiKey) {
        console.error('Error: QWEN_API_KEY not set and no OAuth credentials found');
        console.error('Set QWEN_API_KEY or run: oml qwen keys add');
        process.exit(1);
      }
      
      if (query) {
        await manager.addMessage('user', query);
        console.log(`Sending query to Qwen...`);
        console.log('API integration pending - Qwen API client needed');
      } else {
        console.log(`Interactive chat mode (session: ${sessionId})`);
        console.log('Type your message or "quit" to exit');
      }
    });

  // Session subcommand
  qwen.addCommand(createSessionCommand());

  // Config subcommand
  qwen.addCommand(createConfigCommand());

  // Keys subcommand
  qwen.addCommand(createKeysCommand());

  // MCP subcommand
  qwen
    .command('mcp')
    .description('Manage MCP services')
    .action(() => {
      console.log('MCP management - coming soon');
    });

  // Help subcommand
  qwen
    .command('help')
    .description('Show Qwen help')
    .action(() => {
      qwen.outputHelp();
    });

  return qwen;
}

/**
 * Session subcommand
 */
function createSessionCommand(): Command {
  const session = new Command('session');

  session
    .command('list')
    .description('List sessions')
    .option('-l, --limit <number>', 'Limit results', '10')
    .action(async (options) => {
      const limit = parseInt(options.limit, 10);
      const manager = new SessionManager({ sessionsDir: './sessions' });
      const sessions = await manager.list({ limit });
      
      if (sessions.length === 0) {
        console.log('No sessions found');
        return;
      }

      console.log('Sessions:');
      for (const s of sessions) {
        console.log(`  ${s.id} - ${s.name || 'unnamed'} (${s.status}) - ${s.messages.length} messages`);
      }
    });

  session
    .command('show')
    .description('Show session details')
    .argument('<id>', 'Session ID')
    .action(async (id) => {
      const manager = new SessionManager({ sessionsDir: './sessions' });
      const session = await manager.resume(id);
      console.log(JSON.stringify(session, null, 2));
    });

  session
    .command('switch')
    .description('Switch to session')
    .argument('<id>', 'Session ID')
    .action(async (id) => {
      const manager = new SessionManager({ sessionsDir: './sessions' });
      await manager.switch(id);
      console.log(`Switched to session: ${id}`);
    });

  session
    .command('create')
    .description('Create new session')
    .argument('[name]', 'Session name')
    .action(async (name) => {
      const manager = new SessionManager({ sessionsDir: './sessions' });
      const session = await manager.create({ name });
      console.log(`Created session: ${session.id}`);
    });

  session
    .command('delete')
    .description('Delete session')
    .argument('<id>', 'Session ID')
    .action(async (id) => {
      const manager = new SessionManager({ sessionsDir: './sessions' });
      await manager.delete(id);
      console.log(`Deleted session: ${id}`);
    });

  return session;
}

/**
 * Config subcommand
 */
function createConfigCommand(): Command {
  const config = new Command('config');

  config
    .command('show')
    .description('Show configuration')
    .action(() => {
      console.log('Configuration - coming soon');
    });

  config
    .command('edit')
    .description('Edit configuration')
    .action(() => {
      console.log('Edit configuration - coming soon');
    });

  return config;
}

/**
 * Keys subcommand
 */
function createKeysCommand(): Command {
  const keys = new Command('keys');

  keys
    .command('list')
    .description('List API keys')
    .action(() => {
      console.log('API keys - coming soon');
    });

  keys
    .command('add')
    .description('Add API key')
    .argument('<key>', 'API key')
    .argument('[alias]', 'Key alias')
    .action((key, alias) => {
      console.log(`Add key: ${alias || 'default'} - coming soon`);
    });

  return keys;
}
