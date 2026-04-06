import { describe, it, expect, beforeEach } from 'vitest';
import { MemorySync } from '../src/memory.js';
import { ContextManager } from '../src/context-manager.js';

describe('ContextManager', () => {
  let memory: MemorySync;
  let manager: ContextManager;

  beforeEach(() => {
    memory = new MemorySync();
    manager = new ContextManager(memory);
  });

  // ── generateSummary ────────────────────────────────────────────
  describe('generateSummary', () => {
    it('returns correct ContextSummary with populated data', () => {
      memory.addHistory('INIT', { action: 'start' });
      memory.addHistory('EXECUTION', { action: 'run' });
      memory.addDecision('Use JWT', 'Simpler approach');
      memory.addDecision('Skip OAuth', 'Overkill for now');
      memory.addError('TimeoutError', 'Request timed out', 'Retry');

      const summary = manager.generateSummary();

      expect(summary.currentPhase).toBe('INIT');
      expect(summary.activeSession).toBeNull();
      expect(summary.historyCount).toBe(2);
      expect(summary.decisionCount).toBe(2);
      expect(summary.errorCount).toBe(1);
      expect(summary.keyDecisions).toEqual(['Use JWT', 'Skip OAuth']);
      expect(summary.pendingErrors).toEqual(['Request timed out']);
      expect(summary.lastUpdate).toMatch(/^\d{4}-\d{2}-\d{2}T/);
    });

    it('returns correct summary with empty memory', () => {
      const summary = manager.generateSummary();

      expect(summary.currentPhase).toBe('INIT');
      expect(summary.activeSession).toBeNull();
      expect(summary.historyCount).toBe(0);
      expect(summary.decisionCount).toBe(0);
      expect(summary.errorCount).toBe(0);
      expect(summary.keyDecisions).toEqual([]);
      expect(summary.pendingErrors).toEqual([]);
    });

    it('reflects phase changes', () => {
      manager.setPhase('EXECUTION');
      const summary = manager.generateSummary();
      expect(summary.currentPhase).toBe('EXECUTION');
    });

    it('reflects active session changes', () => {
      manager.setActiveSession('sess_123');
      const summary = manager.generateSummary();
      expect(summary.activeSession).toBe('sess_123');
    });
  });

  // ── getContextForNewSession ────────────────────────────────────
  describe('getContextForNewSession', () => {
    it('returns summary + history + decisions', async () => {
      memory.addHistory('INIT', { step: 1 });
      memory.addHistory('EXECUTION', { step: 2 });
      memory.addDecision('D1', 'R1');

      const result = await manager.getContextForNewSession();

      expect(result.summary).toBeDefined();
      expect(result.summary.historyCount).toBe(2);
      expect(result.summary.decisionCount).toBe(1);
      expect(result.history).toHaveLength(2);
      expect(result.decisions).toHaveLength(1);
    });

    it('works with empty memory', async () => {
      const result = await manager.getContextForNewSession();

      expect(result.summary.historyCount).toBe(0);
      expect(result.history).toHaveLength(0);
      expect(result.decisions).toHaveLength(0);
    });
  });

  // ── shouldEscalate ─────────────────────────────────────────────
  describe('shouldEscalate', () => {
    it('returns true when error count >= 3', () => {
      memory.addError('E1', 'msg1', 'action1');
      memory.addError('E2', 'msg2', 'action2');
      memory.addError('E3', 'msg3', 'action3');

      expect(manager.shouldEscalate()).toBe(true);
    });

    it('returns false when no errors', () => {
      expect(manager.shouldEscalate()).toBe(false);
    });

    it('returns false when error count < 3', () => {
      memory.addError('E1', 'msg1', 'action1');
      memory.addError('E2', 'msg2', 'action2');

      expect(manager.shouldEscalate()).toBe(false);
    });

    it('returns true when decision contains escalate rationale', () => {
      memory.addDecision('Escalate to human', 'Cannot resolve, escalate');

      expect(manager.shouldEscalate()).toBe(true);
    });

    it('returns false when no errors and no escalate decision', () => {
      memory.addDecision('Retry request', 'Standard retry logic');

      expect(manager.shouldEscalate()).toBe(false);
    });
  });
});
