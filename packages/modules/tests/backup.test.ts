import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'fs';
import * as path from 'path';
import { AutoBackup } from '../src/backup/manager.js';

describe('AutoBackup', () => {
  let testDir: string;
  let backup: AutoBackup;

  beforeEach(() => {
    testDir = path.join(process.cwd(), 'test-backup-' + Date.now());
    fs.mkdirSync(testDir, { recursive: true });
    
    // Create test files
    fs.writeFileSync(path.join(testDir, 'file1.txt'), 'content1');
    fs.writeFileSync(path.join(testDir, 'file2.txt'), 'content2');
    
    backup = new AutoBackup({ dataDir: testDir, sourceDir: testDir });
  });

  afterEach(() => {
    fs.rmSync(testDir, { recursive: true, force: true });
  });

  it('should initialize with disabled backup', () => {
    const status = backup.getStatus();
    expect(status.enabled).toBe(false);
  });

  it('should start backup', () => {
    backup.start();
    const status = backup.getStatus();
    expect(status.enabled).toBe(true);
  });

  it('should stop backup', () => {
    backup.start();
    backup.stop();
    const status = backup.getStatus();
    expect(status.enabled).toBe(false);
  });

  it('should run backup', async () => {
    const result = await backup.run();
    
    expect(result.status).toBe('completed');
    expect(result.files).toBeGreaterThan(0);
    expect(result.size).toBeGreaterThan(0);
  });

  it('should list backups', async () => {
    await backup.run();
    
    const backups = backup.list();
    expect(backups.length).toBeGreaterThan(0);
  });

  it('should get backup by ID', async () => {
    const result = await backup.run();
    
    const retrieved = backup.get(result.id);
    expect(retrieved).toBeDefined();
    expect(retrieved?.id).toBe(result.id);
  });

  it('should delete backup', async () => {
    const result = await backup.run();
    
    backup.delete(result.id);
    
    const retrieved = backup.get(result.id);
    expect(retrieved).toBeNull();
  });

  it('should cleanup old backups', async () => {
    backup.configure({ maxBackups: 2 });
    
    await backup.run();
    await backup.run();
    await backup.run();
    
    const backups = backup.list();
    expect(backups.length).toBe(2);
  });

  it('should get status', async () => {
    await backup.run();
    
    const status = backup.getStatus();
    
    expect(status.totalBackups).toBeGreaterThan(0);
    expect(status.totalSize).toBeGreaterThan(0);
    expect(status.lastBackup).toBeDefined();
  });

  it('should configure backup', () => {
    backup.configure({ intervalHours: 12, maxBackups: 5 });
    
    const config = backup.getConfig();
    expect(config.intervalHours).toBe(12);
    expect(config.maxBackups).toBe(5);
  });

  it('should exclude patterns', async () => {
    // Create excluded file
    fs.mkdirSync(path.join(testDir, 'node_modules'), { recursive: true });
    fs.writeFileSync(path.join(testDir, 'node_modules', 'test.js'), 'test');
    
    const result = await backup.run();
    
    // node_modules should be excluded
    const backupFiles = fs.readdirSync(result.path, { recursive: true });
    const hasNodeModules = backupFiles.some(f => f.toString().includes('node_modules'));
    expect(hasNodeModules).toBe(false);
  });
});
