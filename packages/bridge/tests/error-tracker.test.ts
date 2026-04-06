import { describe, it, expect, beforeEach } from 'vitest';
import { ErrorTracker } from '../src/error-tracker.js';

describe('ErrorTracker', () => {
  let tracker: ErrorTracker;

  beforeEach(() => {
    tracker = new ErrorTracker();
  });

  // ── recordError ────────────────────────────────────────────────
  describe('recordError', () => {
    it('creates new pattern', () => {
      tracker.recordError('TimeoutError', 'Request timed out', 'Retry');

      const pattern = tracker.getPattern('TimeoutError');
      expect(pattern).toBeDefined();
      expect(pattern!.type).toBe('TimeoutError');
      expect(pattern!.count).toBe(1);
      expect(pattern!.recoveryAction).toBe('Retry');
      expect(pattern!.recoverySuccess).toBe(false);
      expect(pattern!.lastOccurrence).toMatch(/^\d{4}-\d{2}-\d{2}T/);
    });

    it('increments count for existing pattern', () => {
      tracker.recordError('TimeoutError', 'msg1', 'Retry');
      tracker.recordError('TimeoutError', 'msg2', 'Retry');
      tracker.recordError('TimeoutError', 'msg3', 'Retry');

      const pattern = tracker.getPattern('TimeoutError');
      expect(pattern!.count).toBe(3);
    });

    it('updates lastOccurrence', () => {
      tracker.recordError('TimeoutError', 'msg', 'Retry');
      const firstOccurrence = tracker.getPattern('TimeoutError')!.lastOccurrence;

      // Small delay to ensure different timestamp
      const start = Date.now();
      while (Date.now() - start < 2) { /* spin */ }

      tracker.recordError('TimeoutError', 'msg', 'Retry');
      const secondOccurrence = tracker.getPattern('TimeoutError')!.lastOccurrence;

      expect(secondOccurrence >= firstOccurrence).toBe(true);
    });

    it('resets recoverySuccess on new occurrence', () => {
      tracker.recordError('TimeoutError', 'msg', 'Retry');
      tracker.markRecoverySuccess('TimeoutError');
      expect(tracker.getPattern('TimeoutError')!.recoverySuccess).toBe(true);

      tracker.recordError('TimeoutError', 'msg', 'Retry');
      expect(tracker.getPattern('TimeoutError')!.recoverySuccess).toBe(false);
    });
  });

  // ── getPattern ─────────────────────────────────────────────────
  describe('getPattern', () => {
    it('returns pattern for existing type', () => {
      tracker.recordError('TimeoutError', 'msg', 'Retry');

      const pattern = tracker.getPattern('TimeoutError');
      expect(pattern).toBeDefined();
      expect(pattern!.type).toBe('TimeoutError');
    });

    it('returns undefined for non-existing type', () => {
      expect(tracker.getPattern('NonExistent')).toBeUndefined();
    });
  });

  // ── getAllPatterns ─────────────────────────────────────────────
  describe('getAllPatterns', () => {
    it('returns all patterns', () => {
      tracker.recordError('TimeoutError', 'msg1', 'Retry');
      tracker.recordError('ConnectionError', 'msg2', 'Reconnect');

      const patterns = tracker.getAllPatterns();
      expect(patterns).toHaveLength(2);
      const types = patterns.map((p) => p.type);
      expect(types).toContain('TimeoutError');
      expect(types).toContain('ConnectionError');
    });

    it('returns empty array when no patterns', () => {
      expect(tracker.getAllPatterns()).toEqual([]);
    });
  });

  // ── getEscalationCandidates ────────────────────────────────────
  describe('getEscalationCandidates', () => {
    it('returns patterns with count >= 3 and no successful recovery', () => {
      tracker.recordError('TimeoutError', 'msg', 'Retry');
      tracker.recordError('TimeoutError', 'msg', 'Retry');
      tracker.recordError('TimeoutError', 'msg', 'Retry');

      const candidates = tracker.getEscalationCandidates();
      expect(candidates).toHaveLength(1);
      expect(candidates[0].type).toBe('TimeoutError');
    });

    it('excludes patterns with recoverySuccess', () => {
      tracker.recordError('TimeoutError', 'msg', 'Retry');
      tracker.recordError('TimeoutError', 'msg', 'Retry');
      tracker.recordError('TimeoutError', 'msg', 'Retry');
      tracker.markRecoverySuccess('TimeoutError');

      const candidates = tracker.getEscalationCandidates();
      expect(candidates).toHaveLength(0);
    });

    it('excludes patterns with count < 3', () => {
      tracker.recordError('TimeoutError', 'msg', 'Retry');
      tracker.recordError('TimeoutError', 'msg', 'Retry');

      const candidates = tracker.getEscalationCandidates();
      expect(candidates).toHaveLength(0);
    });
  });

  // ── markRecoverySuccess ────────────────────────────────────────
  describe('markRecoverySuccess', () => {
    it('sets recoverySuccess flag correctly', () => {
      tracker.recordError('TimeoutError', 'msg', 'Retry');
      expect(tracker.getPattern('TimeoutError')!.recoverySuccess).toBe(false);

      tracker.markRecoverySuccess('TimeoutError');
      expect(tracker.getPattern('TimeoutError')!.recoverySuccess).toBe(true);
    });

    it('does nothing for non-existing pattern', () => {
      expect(() => tracker.markRecoverySuccess('NonExistent')).not.toThrow();
    });
  });

  // ── reset ──────────────────────────────────────────────────────
  describe('reset', () => {
    it('clears a specific pattern', () => {
      tracker.recordError('TimeoutError', 'msg', 'Retry');
      tracker.recordError('ConnectionError', 'msg', 'Reconnect');

      tracker.reset('TimeoutError');

      expect(tracker.getPattern('TimeoutError')).toBeUndefined();
      expect(tracker.getPattern('ConnectionError')).toBeDefined();
    });
  });

  // ── clear ──────────────────────────────────────────────────────
  describe('clear', () => {
    it('removes all patterns', () => {
      tracker.recordError('TimeoutError', 'msg', 'Retry');
      tracker.recordError('ConnectionError', 'msg', 'Reconnect');

      tracker.clear();

      expect(tracker.getAllPatterns()).toHaveLength(0);
    });
  });
});
