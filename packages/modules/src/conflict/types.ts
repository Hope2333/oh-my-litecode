/**
 * Conflict Resolver Types - OML Modules
 */

export type ConflictStatus = 'pending' | 'resolved' | 'ignored';
export type ResolveStrategy = 'local' | 'remote' | 'merge' | 'manual';

export interface Conflict {
  id: string;
  file: string;
  localContent: string;
  remoteContent: string;
  baseContent?: string;
  status: ConflictStatus;
  createdAt: Date;
  resolvedAt?: Date;
  strategy?: ResolveStrategy;
  resolvedContent?: string;
}

export interface ConflictList {
  conflicts: Conflict[];
  total: number;
  pending: number;
  resolved: number;
}

export interface ResolveOptions {
  strategy: ResolveStrategy;
  autoResolve?: boolean;
}
