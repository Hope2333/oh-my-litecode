import { describe, it, expect, beforeEach } from 'vitest';
import { MemorySync } from '../src/memory.js';

describe('MemorySync', () => {
  let memory: MemorySync;

  beforeEach(() => {
    memory = new MemorySync();
  });

  // ── addHistory ───────────────────────────────────────────────────
  describe('addHistory', () => {
    it('adds entry with correct type and timestamp', () => {
      memory.addHistory('INIT', { action: 'started' }, 'sess_1');

      const history = memory.getHistory();
      expect(history).toHaveLength(1);
      expect(history[0].type).toBe('history');
      expect(history[0].phase).toBe('INIT');
      expect(history[0].content).toEqual({ action: 'started' });
      expect(history[0].sessionId).toBe('sess_1');
      expect(history[0].timestamp).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/);
    });

    it('adds entry without sessionId', () => {
      memory.addHistory('EXECUTION', { step: 1 });

      const history = memory.getHistory();
      expect(history[0].sessionId).toBeUndefined();
    });
  });

  // ── addContext ───────────────────────────────────────────────────
  describe('addContext', () => {
    it('stores key-value pairs', () => {
      memory.addContext('target', 'opencode', 'sess_1');
      memory.addContext('version', '0.2.0');

      const ctx = memory.getContext();
      expect(ctx).toEqual({ target: 'opencode', version: '0.2.0' });
    });

    it('filters context by key', () => {
      memory.addContext('key1', 'value1');
      memory.addContext('key2', 'value2');

      const ctx = memory.getContext('key1');
      expect(ctx).toEqual({ key1: 'value1' });
    });
  });

  // ── addDecision ──────────────────────────────────────────────────
  describe('addDecision', () => {
    it('stores decision with rationale', () => {
      memory.addDecision('Use JWT auth', 'Simpler than OAuth for this scope', 'sess_1');

      const decisions = memory.getDecisions();
      expect(decisions).toHaveLength(1);
      expect(decisions[0].type).toBe('decision');
      expect(decisions[0].content.decision).toBe('Use JWT auth');
      expect(decisions[0].content.rationale).toBe('Simpler than OAuth for this scope');
    });
  });

  // ── addError ─────────────────────────────────────────────────────
  describe('addError', () => {
    it('stores error with recovery info', () => {
      memory.addError('TimeoutError', 'Request timed out', 'Retry with backoff', 'sess_1');

      const errors = memory.getErrors();
      expect(errors).toHaveLength(1);
      expect(errors[0].type).toBe('error');
      expect(errors[0].content.errorType).toBe('TimeoutError');
      expect(errors[0].content.message).toBe('Request timed out');
      expect(errors[0].content.recoveryAction).toBe('Retry with backoff');
    });
  });

  // ── getHistory ───────────────────────────────────────────────────
  describe('getHistory', () => {
    it('returns entries in order', () => {
      memory.addHistory('INIT', { step: 1 });
      memory.addHistory('EXECUTION', { step: 2 });
      memory.addHistory('REVIEW', { step: 3 });

      const history = memory.getHistory();
      expect(history).toHaveLength(3);
      expect(history[0].phase).toBe('INIT');
      expect(history[1].phase).toBe('EXECUTION');
      expect(history[2].phase).toBe('REVIEW');
    });

    it('respects limit', () => {
      memory.addHistory('INIT', { step: 1 });
      memory.addHistory('EXECUTION', { step: 2 });
      memory.addHistory('REVIEW', { step: 3 });

      const history = memory.getHistory(2);
      expect(history).toHaveLength(2);
      expect(history[0].phase).toBe('EXECUTION');
      expect(history[1].phase).toBe('REVIEW');
    });
  });

  // ── getContext ───────────────────────────────────────────────────
  describe('getContext', () => {
    it('returns all context when no key provided', () => {
      memory.addContext('a', 1);
      memory.addContext('b', 2);

      const ctx = memory.getContext();
      expect(ctx).toEqual({ a: 1, b: 2 });
    });

    it('returns filtered context by key', () => {
      memory.addContext('a', 1);
      memory.addContext('b', 2);

      const ctx = memory.getContext('b');
      expect(ctx).toEqual({ b: 2 });
    });

    it('returns empty object when no context entries', () => {
      expect(memory.getContext()).toEqual({});
    });
  });

  // ── getDecisions ─────────────────────────────────────────────────
  describe('getDecisions', () => {
    it('returns decision entries', () => {
      memory.addDecision('D1', 'R1');
      memory.addDecision('D2', 'R2');

      const decisions = memory.getDecisions();
      expect(decisions).toHaveLength(2);
      expect(decisions[0].content.decision).toBe('D1');
      expect(decisions[1].content.decision).toBe('D2');
    });
  });

  // ── getErrors ────────────────────────────────────────────────────
  describe('getErrors', () => {
    it('returns error entries', () => {
      memory.addError('E1', 'msg1', 'action1');
      memory.addError('E2', 'msg2', 'action2');

      const errors = memory.getErrors();
      expect(errors).toHaveLength(2);
      expect(errors[0].content.errorType).toBe('E1');
      expect(errors[1].content.errorType).toBe('E2');
    });
  });

  // ── getAll ───────────────────────────────────────────────────────
  describe('getAll', () => {
    it('returns all entries', () => {
      memory.addHistory('INIT', {});
      memory.addContext('k', 'v');
      memory.addDecision('D', 'R');
      memory.addError('E', 'msg', 'action');

      const all = memory.getAll(10);
      expect(all).toHaveLength(4);
      expect(all.map((e) => e.type)).toEqual(['history', 'context', 'decision', 'error']);
    });

    it('respects limit', () => {
      memory.addHistory('INIT', {});
      memory.addContext('k', 'v');
      memory.addDecision('D', 'R');

      const all = memory.getAll(2);
      expect(all).toHaveLength(2);
      expect(all[0].type).toBe('context');
      expect(all[1].type).toBe('decision');
    });
  });

  // ── export ───────────────────────────────────────────────────────
  describe('export', () => {
    it('returns all entries as array', () => {
      memory.addHistory('INIT', {});
      memory.addDecision('D', 'R');

      const exported = memory.export();
      expect(exported).toHaveLength(2);
      expect(Array.isArray(exported)).toBe(true);
    });

    it('returns a deep clone (mutations do not affect original)', () => {
      memory.addHistory('INIT', { key: 'value' });

      const exported = memory.export();
      exported[0].content.key = 'mutated';

      const reExported = memory.export();
      expect(reExported[0].content.key).toBe('value');
    });
  });

  // ── import ───────────────────────────────────────────────────────
  describe('import', () => {
    it('restores entries from array', () => {
      const entries = [
        { id: 'mem_1', type: 'history' as const, timestamp: '2024-01-01T00:00:00.000Z', phase: 'INIT', content: {} },
        { id: 'mem_2', type: 'decision' as const, timestamp: '2024-01-01T00:00:01.000Z', phase: '', content: { decision: 'D', rationale: 'R' } },
      ];

      memory.import(entries);

      const all = memory.getAll(10);
      expect(all).toHaveLength(2);
      expect(all[0].id).toBe('mem_1');
      expect(all[1].id).toBe('mem_2');
    });
  });

  // ── clear ────────────────────────────────────────────────────────
  describe('clear', () => {
    it('removes all entries', () => {
      memory.addHistory('INIT', {});
      memory.addContext('k', 'v');
      memory.addDecision('D', 'R');

      memory.clear();

      expect(memory.getAll(10)).toHaveLength(0);
      expect(memory.getHistory()).toHaveLength(0);
      expect(memory.getContext()).toEqual({});
    });
  });

  // ── maxEntries ───────────────────────────────────────────────────
  describe('maxEntries', () => {
    it('limits total entries', () => {
      const smallMemory = new MemorySync(3);

      smallMemory.addHistory('INIT', { step: 1 });
      smallMemory.addHistory('EXECUTION', { step: 2 });
      smallMemory.addHistory('REVIEW', { step: 3 });
      smallMemory.addHistory('DONE', { step: 4 });

      const all = smallMemory.getAll(10);
      expect(all).toHaveLength(3);
      expect(all[0].phase).toBe('EXECUTION');
      expect(all[1].phase).toBe('REVIEW');
      expect(all[2].phase).toBe('DONE');
    });
  });
});
