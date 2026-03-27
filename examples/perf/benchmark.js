#!/usr/bin/env node
/**
 * Performance Benchmark Examples
 */

import { PerfMonitor } from '../../packages/modules/src/perf/monitor.js';
import { SessionManager } from '../../packages/core/src/session/manager.js';

async function runBenchmarks() {
  const monitor = new PerfMonitor({ dataDir: './.oml' });
  monitor.init();

  console.log('=== OML Performance Benchmarks ===\n');

  // Benchmark 1: Session creation
  const sessionResult = await monitor.benchmark('session_create', async () => {
    const manager = new SessionManager({ sessionsDir: './.oml/sessions' });
    await manager.create({ name: 'benchmark-session' });
  });
  console.log(`Session Create: ${sessionResult.duration}ms (${sessionResult.memoryUsed}MB)`);

  // Benchmark 2: Session search with cache
  const cacheResult = await monitor.benchmark('session_search_cached', async () => {
    const manager = new SessionManager({ sessionsDir: './.oml/sessions' });
    await manager.getCachedSession('test-session');
  });
  console.log(`Session Search (cached): ${cacheResult.duration}ms (${cacheResult.memoryUsed}MB)`);

  // Generate report
  const report = await monitor.generateReport('1h');
  console.log(`\nPerformance Score: ${report.summary.score}/100`);
  console.log(`Health: ${report.summary.health}`);
  
  if (report.recommendations.length > 0) {
    console.log('\nRecommendations:');
    report.recommendations.forEach(r => console.log(`  - ${r}`));
  }
}

runBenchmarks().catch(console.error);
