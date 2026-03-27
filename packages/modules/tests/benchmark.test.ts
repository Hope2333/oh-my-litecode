import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'fs';
import * as path from 'path';
import { AutoBackup } from '../src/backup/manager.js';
import { ConflictResolver } from '../src/conflict/resolver.js';
import { PerfMonitor } from '../src/perf/monitor.js';

describe('Benchmark Tests', () => {
  let testDir: string;
  let monitor: PerfMonitor;

  beforeEach(() => {
    testDir = path.join(process.cwd(), 'test-benchmark-' + Date.now());
    fs.mkdirSync(testDir, { recursive: true });
    monitor = new PerfMonitor({ dataDir: testDir });
    monitor.init();
  });

  afterEach(() => {
    fs.rmSync(testDir, { recursive: true, force: true });
  });

  it('should complete backup within performance threshold', async () => {
    const backup = new AutoBackup({ dataDir: testDir, sourceDir: testDir });
    
    // Create test files
    fs.writeFileSync(path.join(testDir, 'file1.txt'), 'content1');
    fs.writeFileSync(path.join(testDir, 'file2.txt'), 'content2');
    
    // Benchmark backup operation
    const result = await monitor.benchmark('backup_run', async () => {
      return backup.run();
    });
    
    // Assert performance threshold (< 1000ms)
    expect(result.duration).toBeLessThan(1000);
    expect(result.memoryUsed).toBeLessThan(100);
  });

  it('should complete conflict resolution within performance threshold', async () => {
    const resolver = new ConflictResolver({ dataDir: testDir });
    
    // Benchmark conflict detection and resolution
    const result = await monitor.benchmark('conflict_resolve', async () => {
      const conflict = resolver.detectConflict('test.json', '{"a":1}', '{"a":2}');
      if (conflict) {
        resolver.resolve(conflict.id, { strategy: 'local' });
      }
    });
    
    // Assert performance threshold (< 100ms)
    expect(result.duration).toBeLessThan(100);
    expect(result.memoryUsed).toBeLessThan(50);
  });

  it('should handle multiple operations within acceptable time', async () => {
    const backup = new AutoBackup({ dataDir: testDir, sourceDir: testDir });
    const resolver = new ConflictResolver({ dataDir: testDir });
    
    // Benchmark multiple operations
    const result = await monitor.benchmark('multi_operation', async () => {
      // Create conflicts
      for (let i = 0; i < 5; i++) {
        resolver.detectConflict(`file${i}.json`, 'local', 'remote');
      }
      
      // Run backup
      await backup.run();
      
      // Resolve all conflicts
      resolver.resolveAll('local');
    });
    
    // Assert performance threshold (< 2000ms for multiple operations)
    expect(result.duration).toBeLessThan(2000);
  });

  it('should maintain cache performance', async () => {
    // Simulate cache operations
    const cache = new Map<string, { data: string; cachedAt: number }>();
    const cacheTTL = 300000;
    
    const result = await monitor.benchmark('cache_operations', async () => {
      // Write to cache
      for (let i = 0; i < 100; i++) {
        cache.set(`key${i}`, { data: `value${i}`, cachedAt: Date.now() });
      }
      
      // Read from cache
      for (let i = 0; i < 100; i++) {
        const item = cache.get(`key${i}`);
        if (item && Date.now() - item.cachedAt < cacheTTL) {
          // Cache hit
          item.data;
        }
      }
    });
    
    // Assert cache performance (< 50ms for 200 operations)
    expect(result.duration).toBeLessThan(50);
  });
});
