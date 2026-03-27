/**
 * Performance Monitor Types - OML Modules
 */

export interface PerfMetrics {
  startupTimeMs: number;
  memoryUsageMb: number;
  cacheHitRate: number;
  commandLatencyMs: number;
  cpuUsagePercent: number;
  diskUsageMb: number;
  lastUpdated: Date;
}

export interface PerfAlert {
  id: string;
  type: 'warning' | 'error' | 'info';
  metric: string;
  value: number;
  threshold: number;
  message: string;
  createdAt: Date;
  acknowledged: boolean;
}

export interface PerfReport {
  generatedAt: Date;
  period: string;
  metrics: PerfMetrics;
  alerts: PerfAlert[];
  recommendations: string[];
  summary: {
    health: 'good' | 'warning' | 'critical';
    score: number;
    topIssues: string[];
  };
}

export interface BenchmarkResult {
  name: string;
  duration: number; // ms
  memoryUsed: number; // MB
  timestamp: Date;
}
