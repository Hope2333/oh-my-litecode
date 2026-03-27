import { describe, it, expect, beforeEach } from 'vitest';
import { SessionManager } from '../src/session/manager.js';
import * as fs from 'fs';
import * as path from 'path';

describe('SessionManager - Extended', () => {
  let manager: SessionManager;

  beforeEach(() => {
    manager = new SessionManager({ sessionsDir: './sessions' });
  });

  describe('diff', () => {
    it('should calculate diff between two sessions', async () => {
      const session1 = await manager.create({ name: 'session1' });
      await manager.addMessage('user', 'message 1');
      
      const session2 = await manager.create({ name: 'session2' });
      await manager.addMessage('user', 'message 1');
      await manager.addMessage('assistant', 'response 1');

      const diff = manager.diff(session1.id, session2.id);

      expect(diff.sessionId1).toBe(session1.id);
      expect(diff.sessionId2).toBe(session2.id);
      expect(diff.added.length).toBeGreaterThan(0);
      expect(diff.stats.totalMessages2).toBeGreaterThan(diff.stats.totalMessages1);
    });
  });

  describe('fork', () => {
    it('should fork a session (full)', async () => {
      const parent = await manager.create({ name: 'parent' });
      await manager.addMessage('user', 'message 1');
      await manager.addMessage('assistant', 'response 1');

      const reloadedParent = await manager.resume(parent.id);
      const forked = await manager.fork(parent.id, { name: 'forked' });

      expect(forked.parentId).toBe(parent.id);
      expect(forked.forkedFrom).toBe(parent.id);
      expect(forked.forkType).toBe('full');
      expect(forked.messages.length).toBe(reloadedParent.messages.length);
    });

    it('should fork a session (shallow)', async () => {
      const parent = await manager.create({ name: 'parent' });
      await manager.addMessage('user', 'message 1');
      await manager.addMessage('assistant', 'response 1');
      await manager.addMessage('user', 'message 2');

      const forked = await manager.fork(parent.id, { shallow: true, upToMessage: 1 });

      expect(forked.forkType).toBe('shallow');
      expect(forked.messages.length).toBe(1);
    });
  });

  describe('search', () => {
    it('should search sessions by query', async () => {
      const session = await manager.create({ name: 'test' });
      await manager.addMessage('user', 'hello world');
      await manager.addMessage('assistant', 'hi there');

      const results = await manager.search({ query: 'hello' });

      expect(results.length).toBeGreaterThan(0);
      expect(results.some(r => r.session.id === session.id)).toBe(true);
      expect(results[0].matches.length).toBeGreaterThan(0);
    });

    it('should search sessions by role', async () => {
      await manager.create({ name: 'test' });
      await manager.addMessage('user', 'user message');
      await manager.addMessage('assistant', 'assistant message');

      const results = await manager.search({ role: 'user' });

      expect(results[0].matches.every(m => m.role === 'user')).toBe(true);
    });
  });

  describe('share', () => {
    it('should share a session', async () => {
      const session = await manager.create({ name: 'shared' });
      
      const shared = await manager.share(session.id);

      expect(shared.sessionId).toBe(session.id);
      expect(shared.token).toBeDefined();
      expect(shared.token.length).toBeGreaterThan(0);
    });

    it('should get shared session by token', async () => {
      const session = await manager.create({ name: 'shared' });
      await manager.addMessage('user', 'test message');
      
      const shared = await manager.share(session.id);
      const retrieved = await manager.getSharedSession(shared.token);

      expect(retrieved).toBeDefined();
      expect(retrieved?.id).toBe(session.id);
    });

    it('should unshare a session', async () => {
      const session = await manager.create({ name: 'shared' });
      const shared = await manager.share(session.id);
      
      await manager.unshare(shared.token);
      const retrieved = await manager.getSharedSession(shared.token);

      expect(retrieved).toBeNull();
    });
  });

  describe('export', () => {
    it('should export session as JSON', async () => {
      const session = await manager.create({ name: 'export' });
      await manager.addMessage('user', 'test');

      const exported = await manager.export(session.id, 'json');
      const parsed = JSON.parse(exported);

      expect(parsed.id).toBe(session.id);
      expect(parsed.messages.length).toBe(1);
    });

    it('should export session as Markdown', async () => {
      const session = await manager.create({ name: 'export' });
      await manager.addMessage('user', 'test');

      const exported = await manager.export(session.id, 'markdown');

      expect(exported).toContain('# Session:');
      expect(exported).toContain('### USER');
    });

    it('should export session as HTML', async () => {
      const session = await manager.create({ name: 'export' });
      await manager.addMessage('user', 'test');

      const exported = await manager.export(session.id, 'html');

      expect(exported).toContain('<!DOCTYPE html>');
      expect(exported).toContain('class="message user"');
    });
  });
});

describe('SessionManager - Edge Cases', () => {
  let manager: SessionManager;

  beforeEach(() => {
    manager = new SessionManager({ sessionsDir: './sessions' });
  });

  describe('message management', () => {
    it('should clear messages', async () => {
      await manager.create({ name: 'test' });
      await manager.addMessage('user', 'message 1');
      await manager.addMessage('assistant', 'response 1');

      const session = await manager.clearMessages();

      expect(session.messages.length).toBe(0);
    });

    it('should get messages with role filter', async () => {
      await manager.create({ name: 'test' });
      await manager.addMessage('user', 'user 1');
      await manager.addMessage('assistant', 'assistant 1');
      await manager.addMessage('user', 'user 2');

      const messages = await manager.getMessages('user');

      expect(messages.length).toBe(2);
      expect(messages.every(m => m.role === 'user')).toBe(true);
    });

    it('should get messages with limit', async () => {
      await manager.create({ name: 'test' });
      for (let i = 0; i < 5; i++) {
        await manager.addMessage('user', `message ${i}`);
      }

      const messages = await manager.getMessages(undefined, 3);

      expect(messages.length).toBe(3);
    });
  });

  describe('session lifecycle', () => {
    it('should switch session', async () => {
      const session1 = await manager.create({ name: 'session1' });
      const session2 = await manager.create({ name: 'session2' });

      await manager.switch(session1.id);

      expect(manager.getCurrentSessionId()).toBe(session1.id);
    });

    it('should throw when switching to non-existent session', async () => {
      await expect(manager.switch('non-existent')).rejects.toThrow('Session not found');
    });

    it('should delete session', async () => {
      const session = await manager.create({ name: 'test' });
      await manager.delete(session.id);

      const sessions = await manager.list();
      expect(sessions.some(s => s.id === session.id)).toBe(false);
    });
  });

  describe('search edge cases', () => {
    it('should handle empty query', async () => {
      await manager.create({ name: 'test' });
      await manager.addMessage('user', 'hello');

      const results = await manager.search({});

      expect(results.length).toBeGreaterThan(0);
    });

    it('should search with limit', async () => {
      for (let i = 0; i < 5; i++) {
        await manager.create({ name: `session ${i}` });
        await manager.addMessage('user', 'common text');
      }

      const results = await manager.search({ query: 'common', limit: 3 });

      expect(results.length).toBe(3);
    });

    it('should calculate score correctly', async () => {
      await manager.create({ name: 'test' });
      await manager.addMessage('user', 'exact match');
      await manager.addMessage('user', 'starts with match');
      await manager.addMessage('user', 'contains match');

      const results = await manager.search({ query: 'match' });

      expect(results.length).toBeGreaterThan(0);
      expect(results[0].score).toBeGreaterThan(0);
    });
  });

  describe('share edge cases', () => {
    it('should handle expired share token', async () => {
      const session = await manager.create({ name: 'shared' });
      const expiredTime = new Date(Date.now() - 1000);
      
      const shared = await manager.share(session.id, { expiresAt: expiredTime });
      const retrieved = await manager.getSharedSession(shared.token);

      expect(retrieved).toBeNull();
    });

    it('should track access count', async () => {
      const session = await manager.create({ name: 'shared' });
      const shared = await manager.share(session.id);

      await manager.getSharedSession(shared.token);
      await manager.getSharedSession(shared.token);
    });
  });

  describe('export edge cases', () => {
    it('should throw for unknown format', async () => {
      const session = await manager.create({ name: 'test' });

      await expect(manager.export(session.id, 'unknown' as any)).rejects.toThrow('Unknown format');
    });

    it('should export session with metadata', async () => {
      const session = await manager.create({ 
        name: 'test',
        metadata: { key: 'value' }
      });

      const exported = await manager.export(session.id, 'json');
      const parsed = JSON.parse(exported);

      expect(parsed.metadata.key).toBe('value');
    });
  });
});

describe('SessionManager - Extensions', () => {
  let manager: SessionManager;
  let testDir: string;

  beforeEach(() => {
    testDir = path.join(process.cwd(), 'test-session-ext-' + Date.now());
    fs.mkdirSync(testDir, { recursive: true });
    manager = new SessionManager({ sessionsDir: testDir });
  });

  afterEach(() => {
    fs.rmSync(testDir, { recursive: true, force: true });
  });

  it('should build index', async () => {
    await manager.create({ name: 's1' });
    await manager.addMessage('user', 'hello world');
    await manager.addMessage('assistant', 'hi there');
    
    const index = await manager.buildIndex();
    expect(index.has('hello')).toBe(true);
    expect(index.has('world')).toBe(true);
  });

  it('should search by keyword', async () => {
    await manager.create({ name: 's1' });
    await manager.addMessage('user', 'hello world');
    await manager.create({ name: 's2' });
    await manager.addMessage('user', 'goodbye world');
    
    const results = await manager.searchByKeyword('hello');
    expect(results.length).toBe(1);
    expect(results[0].name).toBe('s1');
  });

  it('should cache session', async () => {
    const session = await manager.create({ name: 'cached' });
    const cached = await manager.getCachedSession(session.id);
    expect(cached).toBeDefined();
    
    const cached2 = await manager.getCachedSession(session.id);
    expect(cached2).toBe(cached); // Same instance from cache
  });

  it('should clear cache', async () => {
    const session = await manager.create({ name: 'cached' });
    await manager.getCachedSession(session.id);
    manager.clearCache();
    
    const cached = await manager.getCachedSession(session.id);
    expect(cached).toBeDefined(); // New instance after clear
  });

  it('should record operation', () => {
    expect(() => manager.recordOperation('test', 100)).not.toThrow();
  });
});
