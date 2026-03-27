/**
 * Cloud Commands - OML CLI
 */

import { Command } from 'commander';
import { CloudSync } from '@oml/modules/cloud';

export function createCloudCommand(): Command {
  const cloud = new Command('cloud');
  const sync = new CloudSync({ localDir: process.env.OML_DATA_DIR || './.oml' });

  cloud
    .description('Cloud sync commands')
    .hook('preAction', () => {
      // Initialize cloud sync
    });

  cloud
    .command('auth')
    .description('Authenticate with cloud')
    .option('-c, --code <code>', 'Authorization code')
    .action(async (options) => {
      if (!options.code) {
        console.log('Please visit https://oml.dev/auth to get authorization code');
        console.log('Then run: oml cloud auth --code <code>');
        return;
      }
      try {
        const auth = await sync.authenticate(options.code);
        console.log(`✓ Authenticated as user: ${auth.userId}`);
      } catch (error: any) {
        console.error(`✗ Authentication failed: ${error.message}`);
      }
    });

  cloud
    .command('sync')
    .description('Sync with cloud')
    .option('-d, --direction <dir>', 'Sync direction', 'status')
    .action(async (options) => {
      try {
        const result = await sync.sync(options.direction);
        if (result.success) {
          console.log(`✓ Sync ${result.direction}: ${result.status}`);
          if (result.pulled > 0) console.log(`  Pulled: ${result.pulled} files`);
          if (result.pushed > 0) console.log(`  Pushed: ${result.pushed} files`);
          if (result.conflicts.length > 0) console.log(`  Conflicts: ${result.conflicts.length}`);
        } else {
          console.error(`✗ Sync failed: ${result.errors.join(', ')}`);
        }
      } catch (error: any) {
        console.error(`✗ Sync failed: ${error.message}`);
      }
    });

  cloud
    .command('status')
    .description('Show cloud status')
    .action(async () => {
      const status = await sync.getCloudStatus();
      console.log('Cloud Status:');
      console.log(`  Authenticated: ${status.authenticated ? '✓' : '✗'}`);
      if (status.lastSyncAt) console.log(`  Last Sync: ${status.lastSyncAt.toISOString()}`);
      console.log(`  Local Changes: ${status.localChanges}`);
      console.log(`  Remote Changes: ${status.remoteChanges}`);
      console.log(`  Conflicts: ${status.conflicts}`);
    });

  cloud
    .command('config')
    .description('Show cloud configuration')
    .action(() => {
      console.log('Cloud configuration not yet implemented');
    });

  return cloud;
}
