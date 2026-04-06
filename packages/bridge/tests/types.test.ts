import { describe, it, expect } from 'vitest';
import { BridgeError } from '../src/types.js';
import type { BridgeErrorCode } from '../src/types.js';

describe('BridgeError', () => {
  it('extends Error correctly', () => {
    const error = new BridgeError('OML_UNAVAILABLE', 'Service unavailable', 'OML is not running', true);
    expect(error).toBeInstanceOf(Error);
    expect(error).toBeInstanceOf(BridgeError);
    expect(error.name).toBe('BridgeError');
    expect(error.message).toBe('Service unavailable');
  });

  it('has code property set correctly', () => {
    const error = new BridgeError('CAPABILITY_NOT_FOUND', 'Not found', 'Capability missing', false);
    expect(error.code).toBe('CAPABILITY_NOT_FOUND');
  });

  it('has details property set correctly', () => {
    const error = new BridgeError('TASK_TIMEOUT', 'Timed out', 'Task exceeded 30s limit', true);
    expect(error.details).toBe('Task exceeded 30s limit');
  });

  it('has recoverable property set correctly', () => {
    const recoverable = new BridgeError('OML_UNAVAILABLE', 'Unavailable', 'Retry', true);
    const nonRecoverable = new BridgeError('PROTOCOL_ERROR', 'Protocol error', 'Invalid response', false);
    expect(recoverable.recoverable).toBe(true);
    expect(nonRecoverable.recoverable).toBe(false);
  });

  it('preserves stack trace', () => {
    const error = new BridgeError('VERSION_INCOMPATIBLE', 'Version mismatch', 'Drift detected', false);
    expect(error.stack).toBeDefined();
    expect(typeof error.stack).toBe('string');
  });

  it('accepts all BridgeErrorCode union values', () => {
    const codes: BridgeErrorCode[] = [
      'OML_UNAVAILABLE',
      'CAPABILITY_NOT_FOUND',
      'TASK_TIMEOUT',
      'PROTOCOL_ERROR',
      'VERSION_INCOMPATIBLE',
    ];
    codes.forEach((code) => {
      const error = new BridgeError(code, 'test', 'details', true);
      expect(error.code).toBe(code);
    });
  });
});
