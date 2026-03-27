/**
 * Session Manager - OML Core
 * 
 * Manages session lifecycle operations.
 */

import * as crypto from 'crypto';
import type {
  Session,
  Message,
  SessionCreateOptions,
  SessionListOptions,
  SessionDiff,
  ShareOptions,
  SessionForkOptions,
  SessionFork,
  SessionSearchOptions,
  SessionSearchResult,
  SharedSession,
} from './types.js';
import { SessionStorage } from './storage.js';

export interface SessionManagerOptions {
  sessionsDir: string;
}

export class SessionManager {
  private storage: SessionStorage;
  private currentSessionId: string | null = null;
  private sharedSessions: Map<string, SharedSession>;

  constructor(options: SessionManagerOptions) {
    this.storage = new SessionStorage({ sessionsDir: options.sessionsDir });
    this.sharedSessions = new Map();
  }

  /**
   * Generate a unique session ID
   */
  private generateId(): string {
    return `session-${Date.now()}-${process.pid}-${Math.random().toString(36).slice(2, 8)}`;
  }

  /**
   * Generate a share token
   */
  private generateToken(): string {
    return crypto.randomBytes(16).toString('hex');
  }

  /**
   * Create a new session
   */
  async create(options?: SessionCreateOptions): Promise<Session> {
    const session: Session = {
      id: this.generateId(),
      name: options?.name,
      status: 'active',
      createdAt: new Date(),
      updatedAt: new Date(),
      messages: [],
      metadata: options?.metadata || {},
      parentId: options?.parentId,
    };

    await this.storage.save(session);
    this.currentSessionId = session.id;
    
    return session;
  }

  /**
   * Resume an existing session
   */
  async resume(sessionId?: string): Promise<Session> {
    let id = sessionId || this.currentSessionId;
    
    if (!id) {
      const sessions = await this.storage.list();
      if (sessions.length === 0) {
        return this.create();
      }
      id = sessions[0].id;
    }

    const session = await this.storage.load(id);
    
    if (!session) {
      return this.create();
    }

    this.currentSessionId = id;
    return session;
  }

  /**
   * Switch to an existing session
   */
  async switch(sessionId: string): Promise<void> {
    const exists = await this.storage.exists(sessionId);
    
    if (!exists) {
      throw new Error(`Session not found: ${sessionId}`);
    }

    this.currentSessionId = sessionId;
  }

  /**
   * List sessions
   */
  async list(options?: SessionListOptions): Promise<Session[]> {
    let sessions = await this.storage.list();

    if (options?.status) {
      sessions = sessions.filter(s => s.status === options.status);
    }

    if (options?.limit) {
      sessions = sessions.slice(0, options.limit);
    }

    return sessions;
  }

  /**
   * Delete a session
   */
  async delete(sessionId: string): Promise<void> {
    const deleted = await this.storage.delete(sessionId);
    
    if (!deleted) {
      throw new Error(`Session not found: ${sessionId}`);
    }

    if (this.currentSessionId === sessionId) {
      this.currentSessionId = null;
    }
  }

  /**
   * Add a message to the current session
   */
  async addMessage(role: Message['role'], content: string, metadata?: Message['metadata']): Promise<Session> {
    if (!this.currentSessionId) {
      await this.create();
    }

    const session = await this.resume();
    
    const message: Message = {
      role,
      content,
      timestamp: new Date(),
      metadata,
    };

    session.messages.push(message);
    session.updatedAt = new Date();
    
    await this.storage.save(session);
    
    return session;
  }

  /**
   * Get messages from the current session
   */
  async getMessages(role?: Message['role'], limit?: number): Promise<Message[]> {
    if (!this.currentSessionId) {
      return [];
    }

    const session = await this.resume();
    let messages = session.messages;

    if (role) {
      messages = messages.filter(m => m.role === role);
    }

    if (limit) {
      messages = messages.slice(-limit);
    }

    return messages;
  }

  /**
   * Clear messages from the current session
   */
  async clearMessages(): Promise<Session> {
    if (!this.currentSessionId) {
      throw new Error('No active session');
    }

    const session = await this.resume();
    session.messages = [];
    session.updatedAt = new Date();
    
    await this.storage.save(session);
    
    return session;
  }

  /**
   * Export a session
   */
  async export(sessionId: string, format: ShareOptions['format'] = 'json'): Promise<string> {
    const session = await this.resume(sessionId);
    
    if (format === 'json') {
      return JSON.stringify(session, null, 2);
    }

    if (format === 'markdown') {
      return this.exportMarkdown(session);
    }

    if (format === 'html') {
      return this.exportHtml(session);
    }

    throw new Error(`Unknown format: ${format}`);
  }

  /**
   * Calculate diff between two sessions
   */
  diff(sessionId1: string, sessionId2: string): SessionDiff {
    const session1 = this.storage.loadSync(sessionId1);
    const session2 = this.storage.loadSync(sessionId2);

    if (!session1 || !session2) {
      throw new Error('Session not found');
    }

    const messages1 = session1.messages;
    const messages2 = session2.messages;

    // Find added messages (in session2 but not in session1)
    const added = messages2.filter(m2 => 
      !messages1.some(m1 => this.messageEquals(m1, m2))
    );

    // Find removed messages (in session1 but not in session2)
    const removed = messages1.filter(m1 => 
      !messages2.some(m2 => this.messageEquals(m1, m2))
    );

    // Find modified messages (same position, different content)
    const modified: Message[] = [];
    const minLength = Math.min(messages1.length, messages2.length);
    for (let i = 0; i < minLength; i++) {
      if (messages1[i].role === messages2[i].role && 
          messages1[i].content !== messages2[i].content) {
        modified.push(messages2[i]);
      }
    }

    return {
      sessionId1,
      sessionId2,
      added,
      removed,
      modified,
      stats: {
        totalMessages1: messages1.length,
        totalMessages2: messages2.length,
        addedCount: added.length,
        removedCount: removed.length,
        modifiedCount: modified.length,
      },
    };
  }

  /**
   * Fork a session
   */
  async fork(sessionId: string, options?: SessionForkOptions): Promise<SessionFork> {
    const parent = await this.storage.load(sessionId);
    
    if (!parent) {
      throw new Error(`Session not found: ${sessionId}`);
    }

    const forkType: SessionFork['forkType'] = options?.shallow ? 'shallow' : 'full';
    const upToIndex = options?.upToMessage ?? parent.messages.length;

    const forkedSession: SessionFork = {
      id: this.generateId(),
      name: options?.name || `${parent.name} (fork)`,
      status: 'active',
      createdAt: new Date(),
      updatedAt: new Date(),
      messages: forkType === 'full' 
        ? [...parent.messages] 
        : parent.messages.slice(0, upToIndex),
      metadata: { ...parent.metadata },
      parentId: parent.id,
      forkedFrom: parent.id,
      forkedAt: new Date(),
      forkType,
    };

    await this.storage.save(forkedSession);
    this.currentSessionId = forkedSession.id;

    return forkedSession;
  }

  /**
   * Search sessions
   */
  async search(options?: SessionSearchOptions): Promise<SessionSearchResult[]> {
    const sessions = await this.storage.list();
    const results: SessionSearchResult[] = [];

    for (const session of sessions) {
      if (options?.sessionId && session.id !== options.sessionId) {
        continue;
      }

      const matches: Message[] = [];
      let score = 0;

      for (const message of session.messages) {
        if (options?.role && message.role !== options.role) {
          continue;
        }

        if (options?.query) {
          const query = options.query.toLowerCase();
          const content = message.content.toLowerCase();
          
          if (content.includes(query)) {
            matches.push(message);
            score += this.calculateScore(query, content);
          }
        } else {
          matches.push(message);
          score += 1;
        }
      }

      if (matches.length > 0) {
        results.push({
          session,
          matches,
          score,
        });
      }
    }

    // Sort by score descending
    results.sort((a, b) => b.score - a.score);

    if (options?.limit) {
      return results.slice(0, options.limit);
    }

    return results;
  }

  /**
   * Share a session
   */
  async share(sessionId: string, options?: ShareOptions): Promise<SharedSession> {
    const session = await this.storage.load(sessionId);
    
    if (!session) {
      throw new Error(`Session not found: ${sessionId}`);
    }

    const shared: SharedSession = {
      id: this.generateId(),
      sessionId,
      token: this.generateToken(),
      createdAt: new Date(),
      expiresAt: options?.expiresAt,
      accessedCount: 0,
    };

    this.sharedSessions.set(shared.token, shared);

    return shared;
  }

  /**
   * Unshare a session
   */
  async unshare(token: string): Promise<void> {
    this.sharedSessions.delete(token);
  }

  /**
   * Get shared session by token
   */
  async getSharedSession(token: string): Promise<Session | null> {
    const shared = this.sharedSessions.get(token);
    
    if (!shared) {
      return null;
    }

    // Check expiration
    if (shared.expiresAt && shared.expiresAt < new Date()) {
      this.sharedSessions.delete(token);
      return null;
    }

    // Update access count
    shared.accessedCount++;

    return this.storage.load(shared.sessionId);
  }

  /**
   * Get current session ID
   */
  getCurrentSessionId(): string | null {
    return this.currentSessionId;
  }

  /**
   * Get current session
   */
  async getCurrentSession(): Promise<Session | null> {
    if (!this.currentSessionId) {
      return null;
    }
    return this.resume(this.currentSessionId);
  }

  // Private helper methods

  private messageEquals(m1: Message, m2: Message): boolean {
    return m1.role === m2.role && 
           m1.content === m2.content && 
           m1.timestamp.getTime() === m2.timestamp.getTime();
  }

  private calculateScore(query: string, content: string): number {
    // Simple scoring: exact match = 3, starts with = 2, contains = 1
    if (content === query) return 3;
    if (content.startsWith(query)) return 2;
    if (content.includes(query)) return 1;
    return 0;
  }

  private exportMarkdown(session: Session): string {
    let md = `# Session: ${session.name || session.id}\n\n`;
    md += `**ID**: ${session.id}\n`;
    md += `**Created**: ${session.createdAt.toISOString()}\n`;
    md += `**Updated**: ${session.updatedAt.toISOString()}\n`;
    md += `**Messages**: ${session.messages.length}\n\n`;
    md += `---\n\n`;

    for (const msg of session.messages) {
      md += `### ${msg.role.toUpperCase()}\n\n`;
      md += `${msg.content}\n\n`;
    }

    return md;
  }

  // ========== Feature Extensions ==========

  /**
   * Build session index
   */
  async buildIndex(): Promise<Map<string, string[]>> {
    const index = new Map<string, string[]>();
    const sessions = await this.list();
    for (const session of sessions) {
      for (const message of session.messages) {
        const words = message.content.toLowerCase().split(/\s+/);
        for (const word of words) {
          if (!index.has(word)) index.set(word, []);
          if (!index.get(word)!.includes(session.id)) index.get(word)!.push(session.id);
        }
      }
    }
    return index;
  }

  /**
   * Search sessions by keyword
   */
  async searchByKeyword(keyword: string): Promise<Session[]> {
    const sessions = await this.list();
    const keywordLower = keyword.toLowerCase();
    return sessions.filter(session =>
      session.messages.some(m => m.content.toLowerCase().includes(keywordLower))
    );
  }

  // Cache optimization
  private sessionCache = new Map<string, { session: Session; cachedAt: number }>();
  private cacheTTL = 300000; // 5 minutes

  async getCachedSession(sessionId: string): Promise<Session | null> {
    const cached = this.sessionCache.get(sessionId);
    if (cached && Date.now() - cached.cachedAt < this.cacheTTL) return cached.session;
    const session = await this.resume(sessionId);
    this.sessionCache.set(sessionId, { session, cachedAt: Date.now() });
    return session;
  }

  clearCache(): void { this.sessionCache.clear(); }
  setCacheTTL(ttl: number): void { this.cacheTTL = ttl; }

  // Performance monitoring
  recordOperation(operation: string, durationMs: number): void {
    console.log(`[Perf] ${operation}: ${durationMs}ms`);
  }

  private exportHtml(session: Session): string {
    let html = `<!DOCTYPE html>
<html>
<head>
  <title>Session: ${session.name || session.id}</title>
  <style>
    body { font-family: sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; }
    .message { margin: 10px 0; padding: 10px; border-radius: 5px; }
    .user { background: #e3f2fd; }
    .assistant { background: #f5f5f5; }
    .system { background: #fff3e0; }
    .role { font-weight: bold; color: #666; }
  </style>
</head>
<body>
  <h1>Session: ${session.name || session.id}</h1>
  <p><strong>ID</strong>: ${session.id}</p>
  <p><strong>Created</strong>: ${session.createdAt.toISOString()}</p>
  <p><strong>Messages</strong>: ${session.messages.length}</p>
  <hr>
`;

    for (const msg of session.messages) {
      html += `  <div class="message ${msg.role}">
    <div class="role">${msg.role.toUpperCase()}</div>
    <div class="content">${this.escapeHtml(msg.content)}</div>
  </div>
`;
    }

    html += `</body>
</html>`;

    return html;
  }

  private escapeHtml(text: string): string {
    return text
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

}
