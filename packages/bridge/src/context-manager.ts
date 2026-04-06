// ContextManager — Context summary auto-passing for AI-LTC bridge.
// Depends on MemorySync.

import type { MemoryEntry } from './memory.js';
import { MemorySync } from './memory.js';

export interface ContextSummary {
  currentPhase: string;
  activeSession: string | null;
  historyCount: number;
  decisionCount: number;
  errorCount: number;
  lastUpdate: string;
  keyDecisions: string[];
  pendingErrors: string[];
}

export class ContextManager {
  private memory: MemorySync;
  private currentPhase: string;
  private activeSession: string | null;

  constructor(memory: MemorySync) {
    this.memory = memory;
    this.currentPhase = 'INIT';
    this.activeSession = null;
  }

  setPhase(phase: string): void {
    this.currentPhase = phase;
  }

  setActiveSession(sessionId: string | null): void {
    this.activeSession = sessionId;
  }

  generateSummary(): ContextSummary {
    const history = this.memory.getHistory(1);
    const decisions = this.memory.getDecisions(10);
    const errors = this.memory.getErrors(10);

    const keyDecisions = decisions
      .map((d) => (d.content.decision as string) ?? '')
      .filter(Boolean);

    const pendingErrors = errors
      .map((e) => (e.content.message as string) ?? '')
      .filter(Boolean);

    const lastEntry = this.memory.getAll(1)[0];

    return {
      currentPhase: this.currentPhase,
      activeSession: this.activeSession,
      historyCount: this.memory.getHistory().length,
      decisionCount: decisions.length,
      errorCount: errors.length,
      lastUpdate: lastEntry?.timestamp ?? new Date().toISOString(),
      keyDecisions,
      pendingErrors,
    };
  }

  // eslint-disable-next-line @typescript-eslint/require-await
  async getContextForNewSession(): Promise<{
    summary: ContextSummary;
    history: MemoryEntry[];
    decisions: MemoryEntry[];
  }> {
    const summary = this.generateSummary();
    const history = this.memory.getHistory(20);
    const decisions = this.memory.getDecisions(10);

    return { summary, history, decisions };
  }

  shouldEscalate(): boolean {
    const errors = this.memory.getErrors(5);
    if (errors.length >= 3) return true;

    const recentDecisions = this.memory.getDecisions(5);
    const hasRecoveryDecision = recentDecisions.some(
      (d) => {
        const rationale = d.content.rationale as string;
        return rationale?.toLowerCase().includes('escalate');
      },
    );
    if (hasRecoveryDecision) return true;

    return false;
  }
}
