/**
 * Auto Backup Types - OML Modules
 */

export interface BackupConfig {
  enabled: boolean;
  intervalHours: number;
  maxBackups: number;
  lastBackup?: Date;
  backupDir: string;
  includePatterns: string[];
  excludePatterns: string[];
}

export interface Backup {
  id: string;
  name: string;
  path: string;
  createdAt: Date;
  size: number;
  type: 'manual' | 'auto';
  status: 'completed' | 'failed' | 'in-progress';
  files: number;
}

export interface BackupStatus {
  enabled: boolean;
  lastBackup?: Backup;
  nextBackup?: Date;
  totalBackups: number;
  totalSize: number;
}

export interface RestoreOptions {
  overwrite: boolean;
  verify: boolean;
}
