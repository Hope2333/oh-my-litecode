/**
 * Cloud Sync Types - OML Modules
 */

export type SyncStatus = 'synced' | 'local-changed' | 'remote-changed' | 'conflict';

export type SyncDirection = 'pull' | 'push' | 'status';

export interface SyncConfig {
  enabled: boolean;
  remoteUrl: string;
  authFile: string;
  syncInterval?: number; // ms
  autoSync?: boolean;
}

export interface CloudAuth {
  accessToken: string;
  refreshToken?: string;
  expiresAt?: Date;
  userId?: string;
}

export interface SyncItem {
  path: string;
  type: 'file' | 'directory';
  size: number;
  modifiedAt: Date;
  hash: string;
}

export interface SyncResult {
  success: boolean;
  direction: SyncDirection;
  pulled: number;
  pushed: number;
  conflicts: string[];
  errors: string[];
  status: SyncStatus;
}

export interface CloudStatus {
  authenticated: boolean;
  lastSyncAt?: Date;
  localChanges: number;
  remoteChanges: number;
  conflicts: number;
}
