import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'fs';
import * as path from 'path';
import { ConflictResolver } from '../src/conflict/resolver.js';

describe('ConflictResolver', () => {
  let testDir: string;
  let resolver: ConflictResolver;

  beforeEach(() => {
    testDir = path.join(process.cwd(), 'test-conflict-' + Date.now());
    fs.mkdirSync(testDir, { recursive: true });
    resolver = new ConflictResolver({ dataDir: testDir });
  });

  afterEach(() => {
    fs.rmSync(testDir, { recursive: true, force: true });
  });

  it('should initialize with empty conflict list', () => {
    const list = resolver.list();
    expect(list.total).toBe(0);
    expect(list.pending).toBe(0);
  });

  it('should detect conflict', () => {
    const conflict = resolver.detectConflict('test.json', '{"a":1}', '{"a":2}');
    expect(conflict).toBeDefined();
    expect(conflict?.status).toBe('pending');
  });

  it('should not detect conflict for same content', () => {
    const conflict = resolver.detectConflict('test.json', '{"a":1}', '{"a":1}');
    expect(conflict).toBeNull();
  });

  it('should list conflicts', () => {
    resolver.detectConflict('file1.json', 'local1', 'remote1');
    resolver.detectConflict('file2.json', 'local2', 'remote2');
    
    const list = resolver.list();
    expect(list.total).toBe(2);
    expect(list.pending).toBe(2);
  });

  it('should get conflict by ID', () => {
    const conflict = resolver.detectConflict('test.json', 'local', 'remote');
    const retrieved = resolver.get(conflict!.id);
    expect(retrieved).toBeDefined();
    expect(retrieved?.id).toBe(conflict?.id);
  });

  it('should resolve conflict with local strategy', () => {
    const conflict = resolver.detectConflict('test.json', 'local-content', 'remote-content');
    const resolved = resolver.resolve(conflict!.id, { strategy: 'local' });
    expect(resolved?.status).toBe('resolved');
    expect(resolved?.strategy).toBe('local');
    expect(resolved?.resolvedContent).toBe('local-content');
  });

  it('should resolve conflict with remote strategy', () => {
    const conflict = resolver.detectConflict('test.json', 'local', 'remote');
    const resolved = resolver.resolve(conflict!.id, { strategy: 'remote' });
    expect(resolved?.resolvedContent).toBe('remote');
  });

  it('should resolve all conflicts', () => {
    resolver.detectConflict('file1.json', 'local1', 'remote1');
    resolver.detectConflict('file2.json', 'local2', 'remote2');
    
    const count = resolver.resolveAll('local');
    expect(count).toBe(2);
    
    const list = resolver.list();
    expect(list.resolved).toBe(2);
  });

  it('should ignore conflict', () => {
    const conflict = resolver.detectConflict('test.json', 'local', 'remote');
    const result = resolver.ignore(conflict!.id);
    expect(result).toBe(true);
    
    const stats = resolver.getStats();
    expect(stats.ignored).toBe(1);
  });

  it('should delete conflict', () => {
    const conflict = resolver.detectConflict('test.json', 'local', 'remote');
    const result = resolver.delete(conflict!.id);
    expect(result).toBe(true);
    
    const list = resolver.list();
    expect(list.total).toBe(0);
  });

  it('should clear resolved conflicts', () => {
    const c1 = resolver.detectConflict('file1.json', 'local1', 'remote1');
    const c2 = resolver.detectConflict('file2.json', 'local2', 'remote2');
    resolver.resolve(c1!.id, { strategy: 'local' });
    resolver.resolve(c2!.id, { strategy: 'local' });
    
    const count = resolver.clearResolved();
    expect(count).toBe(2);
    
    const list = resolver.list();
    expect(list.total).toBe(0);
  });

  it('should get stats', () => {
    const c1 = resolver.detectConflict('file1.json', 'local1', 'remote1');
    const c2 = resolver.detectConflict('file2.json', 'local2', 'remote2');
    resolver.resolve(c1!.id, { strategy: 'local' });
    resolver.ignore(c2!.id);
    
    const stats = resolver.getStats();
    expect(stats.total).toBe(2);
    expect(stats.resolved).toBe(1);
    expect(stats.ignored).toBe(1);
    expect(stats.pending).toBe(0);
  });

  it('should merge content', () => {
    const conflict = resolver.detectConflict('test.json', 'line1\nline2', 'line1\nline3');
    const resolved = resolver.resolve(conflict!.id, { strategy: 'merge' });
    expect(resolved?.status).toBe('resolved');
  });
});
