/**
 * Error Reporter - OML Modules
 * 
 * Error reporting and logging.
 */

import { Logger, type LogLevel } from '@oml/core';

export interface ErrorReport {
  error: Error;
  context: Record<string, unknown>;
  timestamp: Date;
  severity: 'low' | 'medium' | 'high' | 'critical';
}

export interface ErrorReporterConfig {
  logLevel?: LogLevel;
  reportToConsole?: boolean;
  reportToFile?: boolean;
  file?: string;
}

export class ErrorReporter {
  private logger: Logger;
  private config: ErrorReporterConfig;
  private reports: ErrorReport[] = [];

  constructor(config?: ErrorReporterConfig) {
    this.config = {
      logLevel: 'error',
      reportToConsole: true,
      reportToFile: false,
      ...config,
    };
    this.logger = new Logger({ name: 'oml:error', level: this.config.logLevel });
  }

  report(error: Error | string, context?: Record<string, unknown>, severity: ErrorReport['severity'] = 'medium'): void {
    const err = error instanceof Error ? error : new Error(error);
    
    const report: ErrorReport = {
      error: err,
      context: context || {},
      timestamp: new Date(),
      severity,
    };

    this.reports.push(report);

    if (this.config.reportToConsole) {
      this.logToConsole(report);
    }

    if (this.config.reportToFile && this.config.file) {
      this.logToFile(report);
    }
  }

  private logToConsole(report: ErrorReport): void {
    const severity = report.severity.toUpperCase();
    this.logger.error(`[${severity}] ${report.error.message}`);
    
    if (report.error.stack) {
      this.logger.error(report.error.stack);
    }

    if (Object.keys(report.context).length > 0) {
      this.logger.error(`Context: ${JSON.stringify(report.context)}`);
    }
  }

  private async logToFile(report: ErrorReport): Promise<void> {
    // TODO: Implement file logging
    console.log('File logging - coming soon');
  }

  getReports(): ErrorReport[] {
    return [...this.reports];
  }

  clearReports(): void {
    this.reports = [];
  }

  getReportCount(): number {
    return this.reports.length;
  }

  getReportsBySeverity(severity: ErrorReport['severity']): ErrorReport[] {
    return this.reports.filter(r => r.severity === severity);
  }
}

// Default error reporter instance
let defaultReporter: ErrorReporter | null = null;

export function getDefaultReporter(): ErrorReporter {
  if (!defaultReporter) {
    defaultReporter = new ErrorReporter();
  }
  return defaultReporter;
}

// Convenience functions
export const reportError = (error: Error | string, context?: Record<string, unknown>) => 
  getDefaultReporter().report(error, context);
export const getErrorReports = () => getDefaultReporter().getReports();
export const clearErrorReports = () => getDefaultReporter().clearReports();
