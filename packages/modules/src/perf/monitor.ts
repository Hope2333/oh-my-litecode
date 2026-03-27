/**
 * Performance Monitor - OML Modules
 * 
 * Real-time performance monitoring and optimization.
 */

import * as fs from 'fs';
import * as path from 'path';
import { exec } from 'child_process';
import type {
  PerfMetrics,
  PerfAlert,
  PerfReport,
  BenchmarkResult,
} from './types.js';

export interface PerfMonitorOptions {
  dataDir: string;
  alertThresholds?: {
    memoryMb?: number;
    startupMs?: number;
    latencyMs?: number;
  };
}

export class PerfMonitor {
  private dataDir: string;
  private metricsFile: string;
  private alertsFile: string;
  private thresholds: { memoryMb: number; startupMs: number; latencyMs: number };
  private metrics: PerfMetrics | null = null;

  constructor(options: PerfMonitorOptions) {
    this.dataDir = options.dataDir;
    this.metricsFile = path.join(this.dataDir, 'metrics.json');
    this.alertsFile = path.join(this.dataDir, 'alerts.json');
    this.thresholds = {
      memoryMb: options.alertThresholds?.memoryMb || 512,
      startupMs: options.alertThresholds?.startupMs || 5000,
      latencyMs: options.alertThresholds?.latencyMs || 1000,
    };
    this.ensureDataDir();
    this.loadMetrics();
  }

  private ensureDataDir(): void {
    if (!fs.existsSync(this.dataDir)) {
      fs.mkdirSync(this.dataDir, { recursive: true });
    }
  }

  private loadMetrics(): void {
    try {
      if (fs.existsSync(this.metricsFile)) {
        const data = JSON.parse(fs.readFileSync(this.metricsFile, 'utf-8'));
        this.metrics = {
          ...data,
          lastUpdated: new Date(data.lastUpdated),
        };
      }
    } catch (error) {
      // Ignore invalid metrics file
    }
  }

  private saveMetrics(): void {
    if (this.metrics) {
      fs.writeFileSync(this.metricsFile, JSON.stringify(this.metrics, null, 2));
    }
  }

  private loadAlerts(): PerfAlert[] {
    try {
      if (fs.existsSync(this.alertsFile)) {
        const data = JSON.parse(fs.readFileSync(this.alertsFile, 'utf-8'));
        return data.alerts.map((a: any) => ({
          ...a,
          createdAt: new Date(a.createdAt),
        }));
      }
    } catch (error) {
      // Ignore invalid alerts file
    }
    return [];
  }

  private saveAlerts(alerts: PerfAlert[]): void {
    fs.writeFileSync(this.alertsFile, JSON.stringify({ alerts }, null, 2));
  }

  /**
   * Initialize monitoring
   */
  init(): void {
    if (!fs.existsSync(this.metricsFile)) {
      this.metrics = {
        startupTimeMs: 0,
        memoryUsageMb: 0,
        cacheHitRate: 0,
        commandLatencyMs: 0,
        cpuUsagePercent: 0,
        diskUsageMb: 0,
        lastUpdated: new Date(),
      };
      this.saveMetrics();
    }

    if (!fs.existsSync(this.alertsFile)) {
      this.saveAlerts([]);
    }
  }

  /**
   * Record startup time
   */
  recordStartup(durationMs: number): void {
    this.updateMetrics({ startupTimeMs: durationMs });
    
    if (durationMs > this.thresholds.startupMs) {
      this.createAlert('warning', 'startupTimeMs', durationMs, this.thresholds.startupMs, 'Slow startup detected');
    }
  }

  /**
   * Record command latency
   */
  recordCommandLatency(durationMs: number): void {
    this.updateMetrics({ commandLatencyMs: durationMs });
    
    if (durationMs > this.thresholds.latencyMs) {
      this.createAlert('warning', 'commandLatencyMs', durationMs, this.thresholds.latencyMs, 'High command latency detected');
    }
  }

  /**
   * Update metrics
   */
  updateMetrics(partial: Partial<PerfMetrics>): void {
    if (!this.metrics) {
      this.metrics = {
        startupTimeMs: 0,
        memoryUsageMb: 0,
        cacheHitRate: 0,
        commandLatencyMs: 0,
        cpuUsagePercent: 0,
        diskUsageMb: 0,
        lastUpdated: new Date(),
      };
    }

    Object.assign(this.metrics, partial, { lastUpdated: new Date() });
    this.saveMetrics();
  }

  /**
   * Get current metrics
   */
  getMetrics(): PerfMetrics | null {
    return this.metrics;
  }

  /**
   * Get memory usage
   */
  async getMemoryUsage(): Promise<number> {
    return new Promise((resolve) => {
      const usage = process.memoryUsage();
      resolve(Math.round(usage.heapUsed / 1024 / 1024));
    });
  }

  /**
   * Get CPU usage (simulated for Node.js)
   */
  async getCpuUsage(): Promise<number> {
    // In production, would use os.cpu() or system commands
    // For now, return a simulated value
    return Math.round(Math.random() * 30);
  }

  /**
   * Create alert
   */
  createAlert(type: 'warning' | 'error' | 'info', metric: string, value: number, threshold: number, message: string): void {
    const alerts = this.loadAlerts();
    const alert: PerfAlert = {
      id: `alert-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
      type,
      metric,
      value,
      threshold,
      message,
      createdAt: new Date(),
      acknowledged: false,
    };

    alerts.push(alert);
    this.saveAlerts(alerts);
  }

  /**
   * Acknowledge alert
   */
  acknowledgeAlert(alertId: string): void {
    const alerts = this.loadAlerts();
    const alert = alerts.find(a => a.id === alertId);
    if (alert) {
      alert.acknowledged = true;
      this.saveAlerts(alerts);
    }
  }

  /**
   * Get active alerts
   */
  getActiveAlerts(): PerfAlert[] {
    return this.loadAlerts().filter(a => !a.acknowledged);
  }

  /**
   * Generate performance report
   */
  async generateReport(period: string = '24h'): Promise<PerfReport> {
    const metrics = this.metrics || {
      startupTimeMs: 0,
      memoryUsageMb: 0,
      cacheHitRate: 0,
      commandLatencyMs: 0,
      cpuUsagePercent: 0,
      diskUsageMb: 0,
      lastUpdated: new Date(),
    };

    const alerts = this.getActiveAlerts();
    const recommendations: string[] = [];

    // Generate recommendations based on metrics
    if (metrics.startupTimeMs > this.thresholds.startupMs) {
      recommendations.push('Consider reducing startup overhead by lazy-loading modules');
    }
    if (metrics.commandLatencyMs > this.thresholds.latencyMs) {
      recommendations.push('Optimize command execution by caching results');
    }
    if (metrics.memoryUsageMb > this.thresholds.memoryMb) {
      recommendations.push('Reduce memory usage by clearing unused caches');
    }

    // Calculate health score
    let score = 100;
    score -= alerts.length * 10;
    score -= recommendations.length * 5;
    score = Math.max(0, Math.min(100, score));

    let health: 'good' | 'warning' | 'critical' = 'good';
    if (score < 50) health = 'critical';
    else if (score < 80) health = 'warning';

    return {
      generatedAt: new Date(),
      period,
      metrics,
      alerts,
      recommendations,
      summary: {
        health,
        score,
        topIssues: alerts.slice(0, 3).map(a => a.message),
      },
    };
  }

  /**
   * Run benchmark
   */
  async benchmark(name: string, fn: () => Promise<void>): Promise<BenchmarkResult> {
    const startMemory = process.memoryUsage().heapUsed;
    const startTime = Date.now();

    await fn();

    const duration = Date.now() - startTime;
    const endMemory = process.memoryUsage().heapUsed;
    const memoryUsed = Math.round((endMemory - startMemory) / 1024 / 1024);

    const result: BenchmarkResult = {
      name,
      duration,
      memoryUsed,
      timestamp: new Date(),
    };

    this.recordCommandLatency(duration);

    return result;
  }

  /**
   * Optimize performance
   */
  async optimize(): Promise<string[]> {
    const suggestions: string[] = [];

    // Clear Node.js cache (simulated)
    if (global.gc) {
      global.gc();
      suggestions.push('Garbage collection triggered');
    }

    // Update metrics
    const memory = await this.getMemoryUsage();
    this.updateMetrics({ memoryUsageMb: memory });

    suggestions.push(`Current memory usage: ${memory}MB`);

    return suggestions;
  }

  /**
   * Get status
   */
  async getStatus(): Promise<{
    monitoring: boolean;
    metrics: PerfMetrics | null;
    activeAlerts: number;
  }> {
    return {
      monitoring: this.metrics !== null,
      metrics: this.metrics,
      activeAlerts: this.getActiveAlerts().length,
    };
  }
}
