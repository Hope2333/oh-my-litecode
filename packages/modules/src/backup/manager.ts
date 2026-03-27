/**
 * Auto Backup Manager - OML Modules
 */

import * as fs from 'fs';
import * as path from 'path';
import * as crypto from 'crypto';
import type { BackupConfig, Backup, BackupStatus, RestoreOptions } from './types.js';

export interface AutoBackupOptions {
  dataDir: string;
  sourceDir?: string;
  config?: Partial<BackupConfig>;
}

const DEFAULT_CONFIG: BackupConfig = {
  enabled: false,
  intervalHours: 24,
  maxBackups: 7,
  backupDir: '',
  includePatterns: ['**/*'],
  excludePatterns: ['**/node_modules/**', '**/.git/**', '**/*.log', '**/.test/**'],
};

export class AutoBackup {
  private config: BackupConfig;
  private configFile: string;
  private sourceDir: string;
  private intervalTimer?: NodeJS.Timeout;

  constructor(options: AutoBackupOptions) {
    this.configFile = path.join(options.dataDir, 'backup-config.json');
    this.sourceDir = options.sourceDir || process.cwd();
    this.config = { ...DEFAULT_CONFIG, backupDir: path.join(options.dataDir, 'backups'), ...options.config };
    this.ensureDirs();
    this.loadConfig();
  }

  private ensureDirs(): void {
    if (!fs.existsSync(this.config.backupDir)) fs.mkdirSync(this.config.backupDir, { recursive: true });
    const configDir = path.dirname(this.configFile);
    if (!fs.existsSync(configDir)) fs.mkdirSync(configDir, { recursive: true });
  }

  private loadConfig(): void {
    try {
      if (fs.existsSync(this.configFile)) {
        const data = JSON.parse(fs.readFileSync(this.configFile, 'utf-8'));
        this.config = { ...this.config, ...data };
      }
    } catch {}
  }

  private saveConfig(): void {
    fs.writeFileSync(this.configFile, JSON.stringify(this.config, null, 2));
  }

  start(): void {
    this.config.enabled = true;
    this.saveConfig();
    this.scheduleNextBackup();
  }

  stop(): void {
    this.config.enabled = false;
    this.saveConfig();
    if (this.intervalTimer) { clearInterval(this.intervalTimer); this.intervalTimer = undefined; }
  }

  private scheduleNextBackup(): void {
    if (this.intervalTimer) clearInterval(this.intervalTimer);
    const intervalMs = this.config.intervalHours * 60 * 60 * 1000;
    this.intervalTimer = setInterval(() => { if (this.config.enabled) this.run(); }, intervalMs);
  }

  async run(): Promise<Backup> {
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const backupId = `backup-${timestamp}-${crypto.randomBytes(4).toString('hex')}`;
    const backupPath = path.join(this.config.backupDir, backupId);
    fs.mkdirSync(backupPath, { recursive: true });

    const backup: Backup = { id: backupId, name: backupId, path: backupPath, createdAt: new Date(), size: 0, type: 'auto', status: 'in-progress', files: 0 };

    try {
      const files = this.getFilesToBackup();
      backup.files = files.length;
      for (const file of files) {
        const relativePath = path.relative(this.sourceDir, file);
        const destPath = path.join(backupPath, relativePath + '.bak');
        const destDir = path.dirname(destPath);
        if (!fs.existsSync(destDir)) fs.mkdirSync(destDir, { recursive: true });
        fs.copyFileSync(file, destPath);
        backup.size += fs.statSync(file).size;
      }
      backup.status = 'completed';
      this.config.lastBackup = backup.createdAt;
      this.saveConfig();
      this.cleanupOldBackups();
    } catch (error) {
      backup.status = 'failed';
      throw error;
    }
    return backup;
  }

  private getFilesToBackup(): string[] {
    const files: string[] = [];
    const scanDir = (dir: string) => {
      const entries = fs.readdirSync(dir, { withFileTypes: true });
      for (const entry of entries) {
        const fullPath = path.join(dir, entry.name);
        if (this.shouldExclude(fullPath)) continue;
        if (entry.isDirectory()) scanDir(fullPath);
        else files.push(fullPath);
      }
    };
    if (fs.existsSync(this.sourceDir)) scanDir(this.sourceDir);
    return files;
  }

  private shouldExclude(filePath: string): boolean {
    for (const pattern of this.config.excludePatterns) {
      const regex = new RegExp(pattern.replace(/\*\*/g, '.*').replace(/\*/g, '[^/]*'));
      if (regex.test(filePath)) return true;
    }
    return false;
  }

  private cleanupOldBackups(): void {
    const backups = this.list();
    if (backups.length > this.config.maxBackups) {
      const toDelete = backups.slice(0, backups.length - this.config.maxBackups);
      for (const backup of toDelete) this.delete(backup.id);
    }
  }

  list(): Backup[] {
    const backups: Backup[] = [];
    if (!fs.existsSync(this.config.backupDir)) return backups;
    const entries = fs.readdirSync(this.config.backupDir, { withFileTypes: true });
    for (const entry of entries) {
      if (entry.isDirectory() && entry.name.startsWith('backup-')) {
        const backupPath = path.join(this.config.backupDir, entry.name);
        const backup = this.loadBackup(backupPath);
        if (backup) backups.push(backup);
      }
    }
    backups.sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime());
    return backups;
  }

  private loadBackup(backupPath: string): Backup | null {
    try {
      const entries = fs.readdirSync(backupPath, { recursive: true });
      const files = entries.filter((f): f is string => typeof f === 'string' && f.endsWith('.bak'));
      let size = 0;
      for (const file of files) { size += fs.statSync(path.join(backupPath, file)).size; }
      const stat = fs.statSync(backupPath);
      return { id: path.basename(backupPath), name: path.basename(backupPath), path: backupPath, createdAt: stat.birthtime, size, type: 'auto', status: 'completed', files: files.length };
    } catch { return null; }
  }

  get(id: string): Backup | null {
    const backupPath = path.join(this.config.backupDir, id);
    if (!fs.existsSync(backupPath)) return null;
    return this.loadBackup(backupPath);
  }

  delete(id: string): void {
    const backupPath = path.join(this.config.backupDir, id);
    if (fs.existsSync(backupPath)) fs.rmSync(backupPath, { recursive: true, force: true });
  }

  async restore(id: string, options?: RestoreOptions): Promise<void> {
    const backup = this.get(id);
    if (!backup) throw new Error(`Backup not found: ${id}`);
    const restoreOptions = { overwrite: false, verify: true, ...options };
    const entries = fs.readdirSync(backup.path, { recursive: true });
    for (const entry of entries) {
      if (typeof entry !== 'string' || !entry.endsWith('.bak')) continue;
      const backupFilePath = path.join(backup.path, entry);
      const originalPath = path.join(this.sourceDir, entry.replace(/\.bak$/, ''));
      const originalDir = path.dirname(originalPath);
      if (!fs.existsSync(originalDir)) fs.mkdirSync(originalDir, { recursive: true });
      if (fs.existsSync(originalPath) && !restoreOptions.overwrite) continue;
      fs.copyFileSync(backupFilePath, originalPath);
    }
  }

  getStatus(): BackupStatus {
    const backups = this.list();
    const lastBackup = backups.length > 0 ? backups[0] : undefined;
    const totalSize = backups.reduce((sum, b) => sum + b.size, 0);
    let nextBackup: Date | undefined;
    if (this.config.enabled && lastBackup) nextBackup = new Date(lastBackup.createdAt.getTime() + this.config.intervalHours * 60 * 60 * 1000);
    return { enabled: this.config.enabled, lastBackup, nextBackup, totalBackups: backups.length, totalSize };
  }

  configure(config: Partial<BackupConfig>): void {
    this.config = { ...this.config, ...config };
    this.saveConfig();
    if (config.intervalHours && this.config.enabled) this.scheduleNextBackup();
  }

  getConfig(): BackupConfig { return { ...this.config }; }
}
