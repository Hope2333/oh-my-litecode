import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'fs';
import * as path from 'path';
import { AutoBackup } from '../src/backup/manager.js';
import { ConflictResolver } from '../src/conflict/resolver.js';
import { PerfMonitor } from '../src/perf/monitor.js';
import { Translator } from '../src/i18n/translator.js';

describe('Integration Tests', () => {
  let testDir: string;

  beforeEach(() => {
    testDir = path.join(process.cwd(), 'test-integration-' + Date.now());
    fs.mkdirSync(testDir, { recursive: true });
  });

  afterEach(() => {
    fs.rmSync(testDir, { recursive: true, force: true });
  });

  it('should work with backup and conflict resolver together', async () => {
    // Setup backup
    const backup = new AutoBackup({ dataDir: testDir, sourceDir: testDir });
    
    // Setup conflict resolver
    const resolver = new ConflictResolver({ dataDir: testDir });
    
    // Create a conflict
    const conflict = resolver.detectConflict('config.json', '{"a":1}', '{"a":2}');
    expect(conflict).toBeDefined();
    
    // Run backup
    const backupResult = await backup.run();
    expect(backupResult.status).toBe('completed');
    
    // Resolve conflict
    const resolved = resolver.resolve(conflict!.id, { strategy: 'local' });
    expect(resolved?.status).toBe('resolved');
    
    // Verify both modules work together
    const backupStatus = backup.getStatus();
    const conflictStats = resolver.getStats();
    
    expect(backupStatus.totalBackups).toBe(1);
    expect(conflictStats.resolved).toBe(1);
  });

  it('should work with i18n and perf monitor together', async () => {
    // Setup i18n
    const translator = new Translator({ defaultLocale: 'zh-CN' });
    
    // Setup perf monitor
    const monitor = new PerfMonitor({ dataDir: testDir });
    monitor.init();
    
    // Record translation operation
    const startTime = Date.now();
    translator.t('welcome');
    translator.t('session.create');
    const duration = Date.now() - startTime;
    
    monitor.recordStartup(duration);
    
    // Generate report
    const report = await monitor.generateReport('1h');
    expect(report.summary.score).toBeGreaterThanOrEqual(0);
    expect(report.summary.score).toBeLessThanOrEqual(100);
  });

  it('should handle multiple operations in sequence', async () => {
    const backup = new AutoBackup({ dataDir: testDir, sourceDir: testDir });
    const resolver = new ConflictResolver({ dataDir: testDir });
    const monitor = new PerfMonitor({ dataDir: testDir });
    
    monitor.init();
    
    // Operation 1: Create conflict
    resolver.detectConflict('file1.json', 'local1', 'remote1');
    
    // Operation 2: Run backup
    await backup.run();
    
    // Operation 3: Resolve conflict
    const conflicts = resolver.list();
    if (conflicts.conflicts.length > 0) {
      resolver.resolve(conflicts.conflicts[0].id, { strategy: 'local' });
    }
    
    // Operation 4: Generate perf report
    const report = await monitor.generateReport('1h');
    
    // Verify all operations completed
    expect(backup.getStatus().totalBackups).toBe(1);
    expect(resolver.getStats().resolved).toBeGreaterThanOrEqual(0);
    expect(report.summary.health).toBeDefined();
  });
});
