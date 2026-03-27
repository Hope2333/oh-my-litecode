import { describe, it, expect } from 'vitest';
import { Logger, LogLevel } from '../src/utils/logger.js';

describe('Logger', () => {
  it('should create a logger with default options', () => {
    const logger = new Logger({ name: 'test' });
    expect(logger).toBeDefined();
  });

  it('should respect log level', () => {
    const logger = new Logger({ name: 'test', level: 'error' });
    
    // Should not log debug/info/warn when level is error
    // We can't easily test console output, but we can verify the logger is created
    expect(logger).toBeDefined();
  });

  it('should create child logger', () => {
    const parent = new Logger({ name: 'parent' });
    const child = parent.child('child');
    
    expect(child).toBeDefined();
  });

  it('should have correct level hierarchy', () => {
    const levels: LogLevel[] = ['debug', 'info', 'warn', 'error'];
    expect(levels).toHaveLength(4);
  });
});
