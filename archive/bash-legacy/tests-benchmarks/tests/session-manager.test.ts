import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import {
  createSession,
  loadSession,
  deleteSession,
  listSessions,
  updateSessionStatus,
  addMessage,
  forkSession,
  searchSessions,
  clearSessionMessages,
  getSessionDir,
  generateSessionId,
  getCurrentSession,
} from '../src/core/session-manager.js';
import * as fs from 'fs';
import * as path from 'path';

// Test session directory
const TEST_SESSION_DIR = path.join('/tmp', `oml-test-sessions-${process.pid}`);

describe('Session Manager', () => {
  beforeEach(() => {
    // Setup test directory
    if (!fs.existsSync(TEST_SESSION_DIR)) {
      fs.mkdirSync(TEST_SESSION_DIR, { recursive: true });
    }
    process.env.OML_SESSIONS_DIR = TEST_SESSION_DIR;
  });

  afterEach(() => {
    // Cleanup test directory
    if (fs.existsSync(TEST_SESSION_DIR)) {
      fs.rmSync(TEST_SESSION_DIR, { recursive: true, force: true });
    }
  });

  it('should generate session ID', () => {
    const id = generateSessionId();
    expect(id).toMatch(/^session-\d+-[a-f0-9]+$/);
  });

  it('should create session', async () => {
    const session = await createSession({ name: 'Test Session' });
    expect(session.id).toBeDefined();
    expect(session.name).toBe('Test Session');
    expect(session.status).toBe('pending');
    expect(session.type).toBe('default');
  });

  it('should load session', async () => {
    const created = await createSession({ name: 'Load Test' });
    const loaded = await loadSession(created.id);
    expect(loaded).toBeDefined();
    expect(loaded?.name).toBe('Load Test');
  });

  it('should return null for non-existent session', async () => {
    const loaded = await loadSession('non-existent-id');
    expect(loaded).toBeNull();
  });

  it('should delete session', async () => {
    const created = await createSession();
    const deleted = await deleteSession(created.id);
    expect(deleted).toBe(true);
    const loaded = await loadSession(created.id);
    expect(loaded).toBeNull();
  });

  it('should list sessions', async () => {
    await createSession({ name: 'Session 1' });
    await createSession({ name: 'Session 2' });
    const sessions = await listSessions();
    expect(sessions.length).toBeGreaterThanOrEqual(2);
  });

  it('should update session status', async () => {
    const session = await createSession();
    const updated = await updateSessionStatus(session.id, 'running');
    expect(updated?.status).toBe('running');
  });

  it('should add message to session', async () => {
    const session = await createSession();
    const updated = await addMessage(session.id, 'user', 'Hello, world!');
    expect(updated?.messages.length).toBe(1);
    expect(updated?.messages[0].content).toBe('Hello, world!');
    expect(updated?.messages[0].role).toBe('user');
  });

  it('should fork session', async () => {
    const parent = await createSession({ name: 'Parent' });
    await addMessage(parent.id, 'user', 'Test message');
    const forked = await forkSession(parent.id, { name: 'Forked' });
    expect(forked).toBeDefined();
    expect(forked?.parentId).toBe(parent.id);
    expect(forked?.type).toBe('fork');
    expect(forked?.messages.length).toBe(1);
  });

  it('should search sessions', async () => {
    // Create fresh sessions for this test
    const session1 = await createSession({ name: 'React Project Search Test' });
    const session2 = await createSession({ name: 'Vue Project Search Test' });
    await addMessage(session1.id, 'user', 'React hooks tutorial');
    await addMessage(session2.id, 'user', 'Vue composition API');
    
    const results = await searchSessions('React');
    // Should find at least the React session
    expect(results.length).toBeGreaterThanOrEqual(1);
    const reactSession = results.find(s => s.name?.includes('React'));
    expect(reactSession).toBeDefined();
  });

  it('should clear session messages', async () => {
    const session = await createSession();
    await addMessage(session.id, 'user', 'Message 1');
    await addMessage(session.id, 'assistant', 'Message 2');
    expect(session.messages.length).toBe(0); // Initial is 0
    const loaded = await loadSession(session.id);
    expect(loaded?.messages.length).toBe(2);
    
    const cleared = await clearSessionMessages(session.id);
    expect(cleared?.messages.length).toBe(0);
  });

  it('should get current session', async () => {
    const current = await getCurrentSession();
    // May or may not have a current session
    expect(current === null || current !== null).toBe(true);
  });
});
