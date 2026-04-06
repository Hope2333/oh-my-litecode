// ErrorTracker — Standalone error pattern tracking for AI-LTC bridge.
// No external dependencies.

export interface ErrorPattern {
  type: string;
  count: number;
  lastOccurrence: string;
  recoveryAction: string;
  recoverySuccess: boolean;
}

export class ErrorTracker {
  private patterns: Map<string, ErrorPattern> = new Map();

  recordError(type: string, _message: string, recoveryAction: string): void {
    const existing = this.patterns.get(type);
    if (existing) {
      existing.count += 1;
      existing.lastOccurrence = new Date().toISOString();
      existing.recoveryAction = recoveryAction;
      // Reset success flag on new occurrence — recovery needs re-verification
      existing.recoverySuccess = false;
    } else {
      this.patterns.set(type, {
        type,
        count: 1,
        lastOccurrence: new Date().toISOString(),
        recoveryAction,
        recoverySuccess: false,
      });
    }
  }

  getPattern(type: string): ErrorPattern | undefined {
    return this.patterns.get(type);
  }

  getAllPatterns(): ErrorPattern[] {
    return [...this.patterns.values()];
  }

  getEscalationCandidates(): ErrorPattern[] {
    const threshold = 3;
    return this.getAllPatterns().filter(
      (p) => p.count >= threshold && !p.recoverySuccess,
    );
  }

  markRecoverySuccess(type: string): void {
    const pattern = this.patterns.get(type);
    if (pattern) {
      pattern.recoverySuccess = true;
    }
  }

  reset(type: string): void {
    this.patterns.delete(type);
  }

  clear(): void {
    this.patterns.clear();
  }
}
