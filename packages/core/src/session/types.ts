/**
 * Session Types - OML Core
 * 
 * Type definitions for session management.
 */

export type SessionStatus = 'active' | 'inactive' | 'archived' | 'deleted';

export type MessageRole = 'user' | 'assistant' | 'system';

export interface Message {
  role: MessageRole;
  content: string;
  timestamp: Date;
  metadata?: Record<string, unknown>;
}

export interface Session {
  id: string;
  name?: string;
  status: SessionStatus;
  createdAt: Date;
  updatedAt: Date;
  messages: Message[];
  metadata: Record<string, unknown>;
  parentId?: string;
  forkedFrom?: string;
}

export interface SessionCreateOptions {
  name?: string;
  metadata?: Record<string, unknown>;
  parentId?: string;
}

export interface SessionListOptions {
  limit?: number;
  status?: SessionStatus;
}

export interface SessionDiff {
  sessionId1: string;
  sessionId2: string;
  added: Message[];
  removed: Message[];
  modified: Message[];
  stats: {
    totalMessages1: number;
    totalMessages2: number;
    addedCount: number;
    removedCount: number;
    modifiedCount: number;
  };
}

export interface SessionForkOptions {
  name?: string;
  shallow?: boolean;
  upToMessage?: number;
}

export interface SessionFork extends Session {
  parentId: string;
  forkedAt: Date;
  forkType: 'full' | 'shallow' | 'checkpoint';
}

export interface SessionSearchOptions {
  query?: string;
  role?: MessageRole;
  sessionId?: string;
  limit?: number;
}

export interface SessionSearchResult {
  session: Session;
  matches: Message[];
  score: number;
}

export interface ShareOptions {
  format: 'json' | 'markdown' | 'html';
  includeMetadata?: boolean;
  expiresAt?: Date;
}

export interface SharedSession {
  id: string;
  sessionId: string;
  token: string;
  createdAt: Date;
  expiresAt?: Date;
  accessedCount: number;
}
