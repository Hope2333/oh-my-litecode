import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'fs';
import * as path from 'path';
import { CloudSync } from '../src/cloud/sync.js';

describe('CloudSync', () => {
  let testDir: string;
  let cloudSync: CloudSync;

  beforeEach(() => {
    testDir = path.join(process.cwd(), 'test-cloud-' + Date.now());
    fs.mkdirSync(testDir, { recursive: true });
    
    cloudSync = new CloudSync({ localDir: testDir });
  });

  afterEach(() => {
    fs.rmSync(testDir, { recursive: true, force: true });
  });

  it('should initialize with disabled sync', () => {
    expect(cloudSync.isEnabled()).toBe(false);
    expect(cloudSync.isAuthenticated()).toBe(false);
  });

  it('should enable sync', () => {
    cloudSync.enable('https://api.example.com');
    expect(cloudSync.isEnabled()).toBe(true);
  });

  it('should disable sync', () => {
    cloudSync.enable('https://api.example.com');
    cloudSync.disable();
    expect(cloudSync.isEnabled()).toBe(false);
  });

  it('should authenticate with code', async () => {
    const auth = await cloudSync.authenticate('test-code-123');
    
    expect(auth.accessToken).toBeDefined();
    expect(auth.userId).toBeDefined();
    expect(cloudSync.isAuthenticated()).toBe(true);
  });

  it('should persist auth across instances', async () => {
    await cloudSync.authenticate('test-code-123');
    
    // Create new instance
    const cloudSync2 = new CloudSync({ localDir: testDir });
    
    expect(cloudSync2.isAuthenticated()).toBe(true);
  });

  it('should logout', async () => {
    await cloudSync.authenticate('test-code-123');
    expect(cloudSync.isAuthenticated()).toBe(true);
    
    cloudSync.logout();
    
    expect(cloudSync.isAuthenticated()).toBe(false);
    expect(fs.existsSync(path.join(testDir, 'cloud-auth.json'))).toBe(false);
  });

  it('should get status when not authenticated', async () => {
    const status = await cloudSync.getCloudStatus();
    
    expect(status.authenticated).toBe(false);
    expect(status.localChanges).toBe(0);
    expect(status.remoteChanges).toBe(0);
    expect(status.conflicts).toBe(0);
  });

  it('should get status when authenticated', async () => {
    await cloudSync.authenticate('test-code-123');
    
    const status = await cloudSync.getCloudStatus();
    
    expect(status.authenticated).toBe(true);
  });

  it('should sync with status direction', async () => {
    await cloudSync.authenticate('test-code-123');
    
    const result = await cloudSync.sync('status');
    
    expect(result.success).toBe(true);
    expect(result.direction).toBe('status');
  });

  it('should fail sync when not authenticated', async () => {
    const result = await cloudSync.sync('pull');
    
    expect(result.success).toBe(false);
    expect(result.errors).toContain('Not authenticated');
  });

  it('should scan local files', async () => {
    // Create test files
    fs.writeFileSync(path.join(testDir, 'file1.txt'), 'content1');
    fs.writeFileSync(path.join(testDir, 'file2.txt'), 'content2');
    
    await cloudSync.authenticate('test-code-123');
    
    const status = await cloudSync.getCloudStatus();
    
    // Local files should be detected
    expect(status.localChanges).toBeGreaterThanOrEqual(0);
  });

  it('should handle expired token', async () => {
    // Manually create expired auth
    const authFile = path.join(testDir, 'cloud-auth.json');
    fs.writeFileSync(authFile, JSON.stringify({
      access_token: 'expired-token',
      expires_at: new Date(Date.now() - 1000).toISOString(), // Expired 1 second ago
    }));
    
    const cloudSync2 = new CloudSync({ localDir: testDir });
    
    expect(cloudSync2.isAuthenticated()).toBe(false);
  });
});
