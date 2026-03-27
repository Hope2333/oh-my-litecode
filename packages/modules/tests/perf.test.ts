import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'fs';
import * as path from 'path';
import { PerfMonitor } from '../src/perf/monitor.js';

describe('PerfMonitor', () => {
  let testDir: string;
  let monitor: PerfMonitor;

  beforeEach(() => {
    testDir = path.join(process.cwd(), 'test-perf-' + Date.now());
    fs.mkdirSync(testDir, { recursive: true });
    
    monitor = new PerfMonitor({ 
      dataDir: testDir,
      alertThresholds: {
        memoryMb: 100,
        startupMs: 100,
        latencyMs: 50,
      }
    });
  });

  afterEach(() => {
    fs.rmSync(testDir, { recursive: true, force: true });
  });

  it('should initialize monitoring', () => {
    monitor.init();
    
    expect(fs.existsSync(path.join(testDir, 'metrics.json'))).toBe(true);
    expect(fs.existsSync(path.join(testDir, 'alerts.json'))).toBe(true);
  });

  it('should record startup time', () => {
    monitor.init();
    monitor.recordStartup(50);
    
    const metrics = monitor.getMetrics();
    expect(metrics?.startupTimeMs).toBe(50);
  });

  it('should create alert for slow startup', () => {
    monitor.init();
    monitor.recordStartup(200); // Above threshold of 100
    
    const alerts = monitor.getActiveAlerts();
    expect(alerts.length).toBeGreaterThan(0);
    expect(alerts[0].metric).toBe('startupTimeMs');
  });

  it('should record command latency', () => {
    monitor.init();
    monitor.recordCommandLatency(30);
    
    const metrics = monitor.getMetrics();
    expect(metrics?.commandLatencyMs).toBe(30);
  });

  it('should create alert for high latency', () => {
    monitor.init();
    monitor.recordCommandLatency(100); // Above threshold of 50
    
    const alerts = monitor.getActiveAlerts();
    expect(alerts.length).toBeGreaterThan(0);
    expect(alerts[0].metric).toBe('commandLatencyMs');
  });

  it('should get memory usage', async () => {
    const memory = await monitor.getMemoryUsage();
    
    expect(memory).toBeGreaterThan(0);
    expect(memory).toBeLessThan(10000); // Should be reasonable
  });

  it('should acknowledge alert', () => {
    monitor.init();
    monitor.recordStartup(200);
    
    const alerts = monitor.getActiveAlerts();
    expect(alerts.length).toBeGreaterThan(0);
    
    monitor.acknowledgeAlert(alerts[0].id);
    
    const activeAlerts = monitor.getActiveAlerts();
    expect(activeAlerts.length).toBe(alerts.length - 1);
  });

  it('should generate report', async () => {
    monitor.init();
    monitor.recordStartup(50);
    
    const report = await monitor.generateReport('1h');
    
    expect(report.generatedAt).toBeDefined();
    expect(report.period).toBe('1h');
    expect(report.metrics).toBeDefined();
    expect(report.summary).toBeDefined();
    expect(report.summary.score).toBeGreaterThanOrEqual(0);
    expect(report.summary.score).toBeLessThanOrEqual(100);
  });

  it('should run benchmark', async () => {
    monitor.init();
    
    const result = await monitor.benchmark('test-benchmark', async () => {
      // Simulate work
      await new Promise(resolve => setTimeout(resolve, 10));
    });
    
    expect(result.name).toBe('test-benchmark');
    expect(result.duration).toBeGreaterThanOrEqual(10);
    expect(result.timestamp).toBeDefined();
  });

  it('should optimize performance', async () => {
    monitor.init();
    
    const suggestions = await monitor.optimize();
    
    expect(suggestions.length).toBeGreaterThan(0);
  });

  it('should get status', async () => {
    monitor.init();
    
    const status = await monitor.getStatus();
    
    expect(status.monitoring).toBe(true);
    expect(status.metrics).toBeDefined();
    expect(status.activeAlerts).toBeGreaterThanOrEqual(0);
  });

  it('should persist metrics across instances', () => {
    monitor.init();
    monitor.recordStartup(100);
    
    // Create new instance
    const monitor2 = new PerfMonitor({ dataDir: testDir });
    
    const metrics = monitor2.getMetrics();
    expect(metrics?.startupTimeMs).toBe(100);
  });

  it('should update metrics', () => {
    monitor.init();
    monitor.updateMetrics({ memoryUsageMb: 50, cacheHitRate: 0.8 });
    
    const metrics = monitor.getMetrics();
    expect(metrics?.memoryUsageMb).toBe(50);
    expect(metrics?.cacheHitRate).toBe(0.8);
  });
});
