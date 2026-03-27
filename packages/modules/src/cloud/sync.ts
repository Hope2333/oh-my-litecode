/**
 * Cloud Sync - OML Modules
 * 
 * Syncs local OML configuration with cloud.
 */

import * as fs from 'fs';
import * as path from 'path';
import * as crypto from 'crypto';
import type {
  SyncConfig,
  CloudAuth,
  SyncResult,
  SyncDirection,
  CloudStatus,
  SyncStatus,
} from './types.js';

export interface CloudSyncOptions {
  config?: Partial<SyncConfig>;
  localDir: string;
}

export class CloudSync {
  private config: SyncConfig;
  private localDir: string;
  private auth: CloudAuth | null = null;

  constructor(options: CloudSyncOptions) {
    this.localDir = options.localDir;
    this.config = {
      enabled: false,
      remoteUrl: 'https://api.oml.dev',
      authFile: path.join(this.localDir, 'cloud-auth.json'),
      syncInterval: 3600000, // 1 hour
      autoSync: false,
      ...options.config,
    };
    this.loadAuth();
  }

  private loadAuth(): void {
    try {
      if (fs.existsSync(this.config.authFile)) {
        const data = JSON.parse(fs.readFileSync(this.config.authFile, 'utf-8'));
        this.auth = {
          accessToken: data.access_token,
          refreshToken: data.refresh_token,
          expiresAt: data.expires_at ? new Date(data.expires_at) : undefined,
          userId: data.user_id,
        };
      }
    } catch (error) {
      // Ignore invalid auth file
    }
  }

  private saveAuth(auth: CloudAuth): void {
    const data = {
      access_token: auth.accessToken,
      refresh_token: auth.refreshToken,
      expires_at: auth.expiresAt?.toISOString(),
      user_id: auth.userId,
    };
    
    const authDir = path.dirname(this.config.authFile);
    if (!fs.existsSync(authDir)) {
      fs.mkdirSync(authDir, { recursive: true });
    }
    
    fs.writeFileSync(this.config.authFile, JSON.stringify(data, null, 2));
    fs.chmodSync(this.config.authFile, 0o600);
    this.auth = auth;
  }

  /**
   * Check if authenticated
   */
  isAuthenticated(): boolean {
    if (!this.auth || !this.auth.accessToken) {
      return false;
    }

    if (this.auth.expiresAt && this.auth.expiresAt < new Date()) {
      return false;
    }

    return true;
  }

  /**
   * Authenticate with authorization code
   */
  async authenticate(code: string): Promise<CloudAuth> {
    // In production, this would call the OAuth token endpoint
    // For now, simulate authentication
    const auth: CloudAuth = {
      accessToken: `token_${code}`,
      expiresAt: new Date(Date.now() + 3600000), // 1 hour
      userId: `user_${Date.now()}`,
    };

    this.saveAuth(auth);
    return auth;
  }

  /**
   * Logout
   */
  logout(): void {
    this.auth = null;
    if (fs.existsSync(this.config.authFile)) {
      fs.unlinkSync(this.config.authFile);
    }
  }

  /**
   * Sync with cloud
   */
  async sync(direction: SyncDirection = 'status'): Promise<SyncResult> {
    if (!this.isAuthenticated()) {
      return {
        success: false,
        direction,
        pulled: 0,
        pushed: 0,
        conflicts: [],
        errors: ['Not authenticated'],
        status: 'conflict',
      };
    }

    switch (direction) {
      case 'pull':
        return this.pull();
      case 'push':
        return this.push();
      case 'status':
      default:
        return this.getStatus();
    }
  }

  /**
   * Pull changes from cloud
   */
  private async pull(): Promise<SyncResult> {
    // In production, this would fetch remote changes and merge them
    // For now, simulate pull
    const result: SyncResult = {
      success: true,
      direction: 'pull',
      pulled: 0,
      pushed: 0,
      conflicts: [],
      errors: [],
      status: 'synced',
    };

    // Simulate pulling files
    const remoteFiles = await this.fetchRemoteFiles();
    for (const file of remoteFiles) {
      const localPath = path.join(this.localDir, file.path);
      
      if (fs.existsSync(localPath)) {
        const localHash = this.hashFile(localPath);
        if (localHash !== file.hash) {
          // Conflict - remote and local both changed
          result.conflicts.push(file.path);
          result.status = 'conflict';
        }
      } else {
        // New file from remote
        // In production, would download the file
        result.pulled++;
      }
    }

    if (result.conflicts.length === 0 && result.pulled === 0) {
      result.status = 'synced';
    } else if (result.conflicts.length === 0) {
      result.status = 'remote-changed';
    }

    return result;
  }

  /**
   * Push changes to cloud
   */
  private async push(): Promise<SyncResult> {
    // In production, this would upload local changes
    // For now, simulate push
    const result: SyncResult = {
      success: true,
      direction: 'push',
      pulled: 0,
      pushed: 0,
      conflicts: [],
      errors: [],
      status: 'synced',
    };

    const localFiles = this.scanLocalFiles();
    for (const file of localFiles) {
      // In production, would check if file exists remotely and upload if changed
      result.pushed++;
    }

    if (result.pushed === 0) {
      result.status = 'synced';
    } else {
      result.status = 'local-changed';
    }

    return result;
  }

  /**
   * Get sync status
   */
  private async getStatus(): Promise<SyncResult> {
    const status = await this.getCloudStatus();
    
    let syncStatus: SyncStatus = 'synced';
    if (status.conflicts > 0) {
      syncStatus = 'conflict';
    } else if (status.localChanges > 0) {
      syncStatus = 'local-changed';
    } else if (status.remoteChanges > 0) {
      syncStatus = 'remote-changed';
    }

    return {
      success: true,
      direction: 'status',
      pulled: 0,
      pushed: 0,
      conflicts: status.conflicts > 0 ? ['conflicts-detected'] : [],
      errors: [],
      status: syncStatus,
    };
  }

  /**
   * Get cloud status
   */
  async getCloudStatus(): Promise<CloudStatus> {
    if (!this.isAuthenticated()) {
      return {
        authenticated: false,
        localChanges: 0,
        remoteChanges: 0,
        conflicts: 0,
      };
    }

    const localFiles = this.scanLocalFiles();
    const remoteFiles = await this.fetchRemoteFiles();

    const localChanges = localFiles.filter(f => !remoteFiles.find(r => r.path === f.path && r.hash === f.hash)).length;
    const remoteChanges = remoteFiles.filter(f => !localFiles.find(l => l.path === f.path && l.hash === f.hash)).length;
    const conflicts = localFiles.filter(f => {
      const remote = remoteFiles.find(r => r.path === f.path);
      return remote && remote.hash !== f.hash;
    }).length;

    return {
      authenticated: true,
      lastSyncAt: this.getLastSyncDate(),
      localChanges,
      remoteChanges,
      conflicts,
    };
  }

  /**
   * Scan local files
   */
  private scanLocalFiles(): Array<{ path: string; hash: string; modifiedAt: Date }> {
    const files: Array<{ path: string; hash: string; modifiedAt: Date }> = [];
    
    const scanDir = (dir: string, baseDir: string) => {
      const entries = fs.readdirSync(dir, { withFileTypes: true });
      for (const entry of entries) {
        if (entry.name.startsWith('.')) continue; // Skip hidden files
        
        const fullPath = path.join(dir, entry.name);
        const relativePath = path.relative(baseDir, fullPath);
        
        if (entry.isDirectory()) {
          scanDir(fullPath, baseDir);
        } else {
          files.push({
            path: relativePath,
            hash: this.hashFile(fullPath),
            modifiedAt: fs.statSync(fullPath).mtime,
          });
        }
      }
    };

    if (fs.existsSync(this.localDir)) {
      scanDir(this.localDir, this.localDir);
    }

    return files;
  }

  /**
   * Fetch remote files (simulated)
   */
  private async fetchRemoteFiles(): Promise<Array<{ path: string; hash: string; modifiedAt: Date }>> {
    // In production, this would call the remote API
    // For now, return empty array
    return [];
  }

  /**
   * Hash a file
   */
  private hashFile(filePath: string): string {
    const content = fs.readFileSync(filePath);
    return crypto.createHash('sha256').update(content).digest('hex');
  }

  /**
   * Get last sync date
   */
  private getLastSyncDate(): Date | undefined {
    const syncStateFile = path.join(this.localDir, '.sync-state.json');
    if (fs.existsSync(syncStateFile)) {
      try {
        const data = JSON.parse(fs.readFileSync(syncStateFile, 'utf-8'));
        return data.lastSyncAt ? new Date(data.lastSyncAt) : undefined;
      } catch {
        return undefined;
      }
    }
    return undefined;
  }

  /**
   * Update sync state
   */
  private updateSyncState(): void {
    const syncStateFile = path.join(this.localDir, '.sync-state.json');
    const data = {
      lastSyncAt: new Date().toISOString(),
      version: 1,
    };
    fs.writeFileSync(syncStateFile, JSON.stringify(data, null, 2));
  }

  /**
   * Enable cloud sync
   */
  enable(remoteUrl: string): void {
    this.config.remoteUrl = remoteUrl;
    this.config.enabled = true;
  }

  /**
   * Disable cloud sync
   */
  disable(): void {
    this.config.enabled = false;
  }

  /**
   * Check if sync is enabled
   */
  isEnabled(): boolean {
    return this.config.enabled;
  }
}
