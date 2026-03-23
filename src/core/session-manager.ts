/**
 * OML Session Manager
 * 
 * TypeScript implementation of session lifecycle management
 * Replaces: core/session-manager.sh
 * 
 * Features:
 * - Session CRUD operations
 * - Message history management
 * - Session forking
 * - Session search
 */

import * as fs from 'fs';
import * as path from 'path';
import * as crypto from 'crypto';
import type {
  Session,
  SessionCreateOptions,
  SessionListOptions,
  SessionStatus,
  SessionMessage,
  SessionStorage
} from './session-manager.types';

/**
 * Get session storage directory
 */
export function getSessionDir(): string {
  const omlRoot = process.env.OML_ROOT || path.resolve(__dirname, '../../');
  const configDir = path.join(omlRoot, '.oml', 'sessions');
  
  if (!fs.existsSync(configDir)) {
    fs.mkdirSync(configDir, { recursive: true });
  }
  
  return configDir;
}

/**
 * Generate unique session ID
 */
export function generateSessionId(): string {
  const timestamp = Date.now();
  const random = crypto.randomBytes(8).toString('hex');
  return `session-${timestamp}-${random}`;
}

/**
 * Generate unique message ID
 */
export function generateMessageId(): string {
  const timestamp = Date.now();
  const random = crypto.randomBytes(4).toString('hex');
  return `msg-${timestamp}-${random}`;
}

/**
 * Create a new session
 */
export async function createSession(options: SessionCreateOptions = {}): Promise<Session> {
  const now = Date.now();
  
  const session: Session = {
    id: options.parentId ? `fork-${generateSessionId()}` : generateSessionId(),
    name: options.name,
    type: options.type || 'default',
    status: 'pending',
    createdAt: now,
    updatedAt: now,
    messages: options.messages || [],
    metadata: options.metadata,
    parentId: options.parentId,
  };
  
  // Save session
  await saveSession(session);
  
  return session;
}

/**
 * Save session to disk
 */
export async function saveSession(session: Session): Promise<void> {
  const sessionDir = getSessionDir();
  const sessionFile = path.join(sessionDir, `${session.id}.json`);
  
  session.updatedAt = Date.now();
  
  fs.writeFileSync(sessionFile, JSON.stringify(session, null, 2), 'utf-8');
}

/**
 * Load session from disk
 */
export async function loadSession(id: string): Promise<Session | null> {
  const sessionDir = getSessionDir();
  const sessionFile = path.join(sessionDir, `${id}.json`);
  
  if (!fs.existsSync(sessionFile)) {
    return null;
  }
  
  try {
    const content = fs.readFileSync(sessionFile, 'utf-8');
    return JSON.parse(content) as Session;
  } catch (error) {
    console.error(`Failed to load session: ${id}`);
    console.error(error);
    return null;
  }
}

/**
 * Delete session
 */
export async function deleteSession(id: string): Promise<boolean> {
  const sessionDir = getSessionDir();
  const sessionFile = path.join(sessionDir, `${id}.json`);
  
  if (!fs.existsSync(sessionFile)) {
    return false;
  }
  
  fs.unlinkSync(sessionFile);
  return true;
}

/**
 * List sessions
 */
export async function listSessions(options: SessionListOptions = {}): Promise<Session[]> {
  const sessionDir = getSessionDir();
  const sessions: Session[] = [];
  
  if (!fs.existsSync(sessionDir)) {
    return sessions;
  }
  
  const files = fs.readdirSync(sessionDir);
  
  for (const file of files) {
    if (!file.endsWith('.json')) continue;
    
    const sessionId = file.replace('.json', '');
    const session = await loadSession(sessionId);
    
    if (!session) continue;
    
    // Apply filters
    if (options.status && session.status !== options.status) continue;
    if (options.type && session.type !== options.type) continue;
    
    sessions.push(session);
  }
  
  // Sort
  sessions.sort((a, b) => {
    const order = options.order === 'asc' ? 1 : -1;
    return (b.createdAt - a.createdAt) * order;
  });
  
  // Apply limit
  if (options.limit) {
    return sessions.slice(0, options.limit);
  }
  
  return sessions;
}

/**
 * Get current session (most recent running or pending)
 */
export async function getCurrentSession(): Promise<Session | null> {
  const sessions = await listSessions({ limit: 10 });
  
  // Find first running or pending session
  for (const session of sessions) {
    if (session.status === 'running' || session.status === 'pending') {
      return session;
    }
  }
  
  // Return most recent if no running/pending
  return sessions[0] || null;
}

/**
 * Update session status
 */
export async function updateSessionStatus(
  id: string, 
  status: SessionStatus
): Promise<Session | null> {
  const session = await loadSession(id);
  
  if (!session) {
    return null;
  }
  
  session.status = status;
  
  if (status === 'completed' || status === 'failed' || status === 'cancelled') {
    session.completedAt = Date.now();
  }
  
  await saveSession(session);
  return session;
}

/**
 * Add message to session
 */
export async function addMessage(
  sessionId: string,
  role: 'user' | 'assistant' | 'system',
  content: string,
  metadata?: Record<string, unknown>
): Promise<Session | null> {
  const session = await loadSession(sessionId);
  
  if (!session) {
    return null;
  }
  
  const message: SessionMessage = {
    id: generateMessageId(),
    role,
    content,
    timestamp: Date.now(),
    metadata,
  };
  
  session.messages.push(message);
  session.status = 'running';
  
  await saveSession(session);
  return session;
}

/**
 * Fork session (create copy with parent reference)
 */
export async function forkSession(
  parentId: string,
  options: { name?: string; messages?: SessionMessage[] } = {}
): Promise<Session | null> {
  const parent = await loadSession(parentId);
  
  if (!parent) {
    return null;
  }
  
  const newSession: Session = {
    id: generateSessionId(),
    name: options.name || `${parent.name || 'Session'} (fork)`,
    type: 'fork',
    status: 'pending',
    createdAt: Date.now(),
    updatedAt: Date.now(),
    messages: options.messages || [...parent.messages],
    metadata: { ...parent.metadata },
    parentId: parent.id,
  };
  
  // Add to parent's children
  if (!parent.children) {
    parent.children = [];
  }
  parent.children.push(newSession.id);
  await saveSession(parent);
  
  await saveSession(newSession);
  return newSession;
}

/**
 * Search sessions by content
 */
export async function searchSessions(query: string): Promise<Session[]> {
  const sessions = await listSessions();
  const results: Session[] = [];
  
  const queryLower = query.toLowerCase();
  
  for (const session of sessions) {
    // Search in name
    if (session.name?.toLowerCase().includes(queryLower)) {
      results.push(session);
      continue;
    }
    
    // Search in messages
    for (const message of session.messages) {
      if (message.content.toLowerCase().includes(queryLower)) {
        results.push(session);
        break;
      }
    }
  }
  
  return results;
}

/**
 * Clear session messages
 */
export async function clearSessionMessages(id: string): Promise<Session | null> {
  const session = await loadSession(id);
  
  if (!session) {
    return null;
  }
  
  session.messages = [];
  session.status = 'pending';
  
  await saveSession(session);
  return session;
}

// CLI export
if (import.meta.url === `file://${process.argv[1]}`) {
  const action = process.argv[2] || 'list';
  
  (async () => {
    switch (action) {
      case 'create':
        const newSession = await createSession({
          name: process.argv[3],
        });
        console.log(`Created session: ${newSession.id}`);
        console.log(`Name: ${newSession.name || 'Untitled'}`);
        console.log(`Status: ${newSession.status}`);
        break;
        
      case 'list':
        const sessions = await listSessions();
        console.log(`Found ${sessions.length} session(s):\n`);
        for (const session of sessions) {
          console.log(`${session.id} | ${session.name || 'Untitled'} | ${session.status} | ${new Date(session.createdAt).toISOString()}`);
        }
        break;
        
      case 'current':
        const current = await getCurrentSession();
        if (current) {
          console.log(`Current session: ${current.id}`);
          console.log(`Name: ${current.name || 'Untitled'}`);
          console.log(`Status: ${current.status}`);
          console.log(`Messages: ${current.messages.length}`);
        } else {
          console.log('No active session');
        }
        break;
        
      case 'delete':
        if (!process.argv[3]) {
          console.error('Usage: session-manager delete <session-id>');
          process.exit(1);
        }
        const deleted = await deleteSession(process.argv[3]);
        console.log(deleted ? 'Session deleted' : 'Session not found');
        break;
        
      case 'search':
        if (!process.argv[3]) {
          console.error('Usage: session-manager search <query>');
          process.exit(1);
        }
        const results = await searchSessions(process.argv[3]);
        console.log(`Found ${results.length} matching session(s):\n`);
        for (const session of results) {
          console.log(`${session.id} | ${session.name || 'Untitled'}`);
        }
        break;
        
      default:
        console.log('OML Session Manager');
        console.log('\nUsage: session-manager <action> [args]');
        console.log('\nActions:');
        console.log('  create [name]     Create new session');
        console.log('  list              List all sessions');
        console.log('  current           Show current session');
        console.log('  delete <id>       Delete session');
        console.log('  search <query>    Search sessions');
        console.log('  clear <id>        Clear session messages');
    }
  })();
}
