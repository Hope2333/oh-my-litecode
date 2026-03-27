/**
 * Logger Module - OML Core
 * 
 * Provides structured logging with levels and formatting.
 */

export type LogLevel = 'debug' | 'info' | 'warn' | 'error';

export interface LoggerOptions {
  name: string;
  level?: LogLevel;
  timestamp?: boolean;
  color?: boolean;
}

export class Logger {
  private name: string;
  private level: LogLevel;
  private timestamp: boolean;
  private color: boolean;

  private static LEVELS: Record<LogLevel, number> = {
    debug: 0,
    info: 1,
    warn: 2,
    error: 3,
  };

  private static COLORS = {
    debug: '\x1b[36m',   // Cyan
    info: '\x1b[32m',    // Green
    warn: '\x1b[33m',    // Yellow
    error: '\x1b[31m',   // Red
    reset: '\x1b[0m',
  };

  constructor(options: LoggerOptions) {
    this.name = options.name;
    this.level = options.level ?? 'info';
    this.timestamp = options.timestamp ?? true;
    this.color = options.color ?? true;
  }

  private shouldLog(level: LogLevel): boolean {
    return Logger.LEVELS[level] >= Logger.LEVELS[this.level];
  }

  private formatLevel(level: LogLevel): string {
    const levelStr = level.toUpperCase().padEnd(5);
    if (!this.color) return levelStr;
    
    const color = Logger.COLORS[level];
    const reset = Logger.COLORS.reset;
    return `${color}${levelStr}${reset}`;
  }

  private formatTimestamp(): string {
    if (!this.timestamp) return '';
    return `[${new Date().toISOString()}] `;
  }

  private formatMessage(level: LogLevel, message: string): string {
    const timestamp = this.formatTimestamp();
    const levelStr = this.formatLevel(level);
    return `${timestamp}[${this.name}] ${levelStr}: ${message}`;
  }

  debug(message: string): void {
    if (this.shouldLog('debug')) {
      console.log(this.formatMessage('debug', message));
    }
  }

  info(message: string): void {
    if (this.shouldLog('info')) {
      console.log(this.formatMessage('info', message));
    }
  }

  warn(message: string): void {
    if (this.shouldLog('warn')) {
      console.warn(this.formatMessage('warn', message));
    }
  }

  error(message: string): void {
    if (this.shouldLog('error')) {
      console.error(this.formatMessage('error', message));
    }
  }

  child(name: string): Logger {
    return new Logger({
      ...this,
      name: `${this.name}:${name}`,
    });
  }
}

// Default logger instance
let defaultLogger: Logger | null = null;

export function getDefaultLogger(): Logger {
  if (!defaultLogger) {
    defaultLogger = new Logger({ name: 'oml', level: 'info' });
  }
  return defaultLogger;
}

export function setDefaultLogger(logger: Logger): void {
  defaultLogger = logger;
}

// Convenience functions
export const debug = (message: string) => getDefaultLogger().debug(message);
export const info = (message: string) => getDefaultLogger().info(message);
export const warn = (message: string) => getDefaultLogger().warn(message);
export const error = (message: string) => getDefaultLogger().error(message);
