import { Command } from 'commander';

export function createBridgeCommand(): Command {
  const cmd = new Command('bridge');
  cmd.description('AI-LTC Bridge management');

  cmd.command('status')
    .description('Show bridge status')
    .action(async () => {
      const { OmlBridge } = await import('@oml/bridge');
      const bridge = new OmlBridge();
      try {
        await bridge.initialize();
        const status = await bridge.getStatus();
        console.log('Bridge Status:');
        console.log(`  Enabled: ${status.enabled}`);
        console.log(`  Phase: ${status.phase ?? 'none'}`);
        console.log(`  Config: ${status.config ? 'loaded' : 'not loaded'}`);
      } catch (err) {
        console.error(`Bridge not available: ${(err as Error).message}`);
        process.exit(1);
      }
    });

  cmd.command('info')
    .description('Show bridge configuration')
    .action(async () => {
      const { loadBridgeConfig, checkVersionCompatibility } = await import('@oml/bridge');
      const config = await loadBridgeConfig();
      console.log('Bridge Configuration:');
      console.log(`  AI-LTC Root: ${config.aiLtcRoot}`);
      console.log(`  Config File: ${config.configFile}`);
      console.log(`  Auto Start: ${config.autoStart}`);
      console.log(`  Log Level: ${config.logLevel}`);

      const versionInfo = await checkVersionCompatibility(config.aiLtcRoot, config.configFile);
      console.log('\nVersion Compatibility:');
      console.log(`  Framework: ${versionInfo.framework}`);
      console.log(`  Bridge: ${versionInfo.bridge}`);
      console.log(`  Compatible: ${versionInfo.compatible ? 'yes' : 'no'}`);
    });

  cmd.command('test')
    .description('Test bridge functionality')
    .action(async () => {
      const { OmlBridge } = await import('@oml/bridge');
      const bridge = new OmlBridge();
      try {
        await bridge.initialize();
        console.log('Bridge initialized successfully.');
        console.log('Testing transition: INIT → EXECUTION...');
        await bridge.transition('EXECUTION', { test: true });
        console.log('Transition test passed.');
      } catch (err) {
        console.error(`Bridge test failed: ${(err as Error).message}`);
        process.exit(1);
      }
    });

  cmd.command('start')
    .description('Start watching for AI-LTC state changes')
    .action(async () => {
      const { OmlBridge } = await import('@oml/bridge');
      const bridge = new OmlBridge();
      try {
        await bridge.initialize();
        console.log('Bridge initialized. Watching for state changes...');
        await bridge.start();

        process.on('SIGINT', async () => {
          console.log('\nStopping bridge...');
          await bridge.dispose();
          process.exit(0);
        });
      } catch (err) {
        console.error(`Failed to start bridge: ${(err as Error).message}`);
        process.exit(1);
      }
    });

  return cmd;
}
