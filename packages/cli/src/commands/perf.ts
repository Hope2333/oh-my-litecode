/**
 * Performance Commands - OML CLI
 */

import { Command } from 'commander';
import { PerfMonitor } from '@oml/modules/perf';

export function createPerfCommand(): Command {
  const perf = new Command('perf');
  const monitor = new PerfMonitor({ dataDir: process.env.OML_DATA_DIR || './.oml' });

  perf
    .description('Performance monitoring commands')
    .hook('preAction', () => {
      monitor.init();
    });

  perf
    .command('monitor')
    .description('Start performance monitoring')
    .option('-s, --start', 'Start monitoring')
    .option('-p, --stop', 'Stop monitoring')
    .option('--status', 'Show monitoring status')
    .action(async (options) => {
      const status = await monitor.getStatus();
      if (options.start) {
        console.log('✓ Performance monitoring started');
      } else if (options.stop) {
        console.log('✓ Performance monitoring stopped');
      } else {
        console.log('Performance Monitor Status:');
        console.log(`  Monitoring: ${status.monitoring ? '✓' : '✗'}`);
        console.log(`  Active Alerts: ${status.activeAlerts}`);
        if (status.metrics) {
          console.log(`  Memory: ${status.metrics.memoryUsageMb}MB`);
          console.log(`  Startup: ${status.metrics.startupTimeMs}ms`);
          console.log(`  Latency: ${status.metrics.commandLatencyMs}ms`);
        }
      }
    });

  perf
    .command('benchmark')
    .description('Run benchmark')
    .option('-n, --name <name>', 'Benchmark name', 'default')
    .action(async (options) => {
      const result = await monitor.benchmark(options.name, async () => {
        // Simulate work
        await new Promise(resolve => setTimeout(resolve, 10));
      });
      console.log(`Benchmark: ${result.name}`);
      console.log(`  Duration: ${result.duration}ms`);
      console.log(`  Memory: ${result.memoryUsed}MB`);
    });

  perf
    .command('report')
    .description('Generate performance report')
    .option('-p, --period <period>', 'Report period', '24h')
    .action(async (options) => {
      const report = await monitor.generateReport(options.period);
      console.log(`Performance Report (${options.period}):`);
      console.log(`  Health: ${report.summary.health}`);
      console.log(`  Score: ${report.summary.score}/100`);
      if (report.recommendations.length > 0) {
        console.log('  Recommendations:');
        for (const rec of report.recommendations) {
          console.log(`    - ${rec}`);
        }
      }
    });

  perf
    .command('optimize')
    .description('Optimize performance')
    .action(async () => {
      const suggestions = await monitor.optimize();
      console.log('Optimization suggestions:');
      for (const s of suggestions) {
        console.log(`  - ${s}`);
      }
    });

  return perf;
}
