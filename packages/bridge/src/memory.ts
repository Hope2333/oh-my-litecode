// MemorySync — In-memory entry store for AI-LTC bridge state tracking.
// Standalone: no external dependencies.

export interface MemoryEntry {
  id: string;
  type: 'history' | 'context' | 'decision' | 'error';
  timestamp: string;
  phase: string;
  content: Record<string, unknown>;
  sessionId?: string;
}

let _seq = 0;

function generateId(): string {
  return `mem_${Date.now().toString(36)}_${(++_seq).toString(36)}`;
}

export class MemorySync {
  private entries: MemoryEntry[] = [];
  private maxEntries: number;

  constructor(maxEntries = 10_000) {
    this.maxEntries = maxEntries;
  }

  // ── Add entries ──────────────────────────────────────────────

  addHistory(phase: string, content: Record<string, unknown>, sessionId?: string): void {
    this._push({
      id: generateId(),
      type: 'history',
      timestamp: new Date().toISOString(),
      phase,
      content,
      sessionId,
    });
  }

  addContext(key: string, value: unknown, sessionId?: string): void {
    this._push({
      id: generateId(),
      type: 'context',
      timestamp: new Date().toISOString(),
      phase: '',
      content: { key, value },
      sessionId,
    });
  }

  addDecision(decision: string, rationale: string, sessionId?: string): void {
    this._push({
      id: generateId(),
      type: 'decision',
      timestamp: new Date().toISOString(),
      phase: '',
      content: { decision, rationale },
      sessionId,
    });
  }

  addError(errorType: string, message: string, recoveryAction: string, sessionId?: string): void {
    this._push({
      id: generateId(),
      type: 'error',
      timestamp: new Date().toISOString(),
      phase: '',
      content: { errorType, message, recoveryAction },
      sessionId,
    });
  }

  // ── Query entries ────────────────────────────────────────────

  getHistory(limit = 50): MemoryEntry[] {
    return this._filterByType('history', limit);
  }

  getContext(key?: string): Record<string, unknown> {
    const entries = key
      ? this.entries.filter((e) => e.type === 'context' && e.content.key === key)
      : this.entries.filter((e) => e.type === 'context');
    const result: Record<string, unknown> = {};
    for (const entry of entries) {
      const k = entry.content.key as string;
      result[k] = entry.content.value;
    }
    return result;
  }

  getDecisions(limit = 50): MemoryEntry[] {
    return this._filterByType('decision', limit);
  }

  getErrors(limit = 50): MemoryEntry[] {
    return this._filterByType('error', limit);
  }

  getAll(limit = 100): MemoryEntry[] {
    const slice = this.entries.slice(-limit);
    return [...slice];
  }

  // ── Sync with OML sessions ───────────────────────────────────

  // eslint-disable-next-line @typescript-eslint/require-await
  async syncWithSession(_sessionId: string): Promise<void> {
    // Bridge-side placeholder — actual OML session integration
    // is handled by the OML layer, not the bridge package.
    // This method exists so the interface is complete for future wiring.
  }

  export(): MemoryEntry[] {
    return structuredClone(this.entries);
  }

  import(entries: MemoryEntry[]): void {
    this.entries = [...entries];
    this._trim();
  }

  // ── Cleanup ──────────────────────────────────────────────────

  clear(): void {
    this.entries = [];
  }

  // ── Private helpers ──────────────────────────────────────────

  private _push(entry: MemoryEntry): void {
    this.entries.push(entry);
    this._trim();
  }

  private _trim(): void {
    if (this.entries.length > this.maxEntries) {
      this.entries = this.entries.slice(-this.maxEntries);
    }
  }

  private _filterByType(type: MemoryEntry['type'], limit: number): MemoryEntry[] {
    const filtered = this.entries.filter((e) => e.type === type);
    return filtered.slice(-limit);
  }
}
