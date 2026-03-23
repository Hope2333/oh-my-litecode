/**
 * OML Session Types
 * 
 * Type definitions for session management
 */

export type SessionStatus = 
  | 'pending'
  | 'running'
  | 'completed'
  | 'failed'
  | 'cancelled';

export type SessionType = 
  | 'default'
  | 'fork'
  | 'shared'
  | 'task';

export interface SessionMessage {
  /** Message ID */
  id: string;
  /** Role (user/assistant/system) */
  role: 'user' | 'assistant' | 'system';
  /** Message content */
  content: string;
  /** Timestamp */
  timestamp: number;
  /** Metadata */
  metadata?: Record<string, unknown>;
}

export interface Session {
  /** Session ID */
  id: string;
  /** Session name/title */
  name?: string;
  /** Session type */
  type: SessionType;
  /** Current status */
  status: SessionStatus;
  /** Created timestamp */
  createdAt: number;
  /** Updated timestamp */
  updatedAt: number;
  /** Completed timestamp */
  completedAt?: number;
  /** Messages */
  messages: SessionMessage[];
  /** Metadata */
  metadata?: {
    platform?: string;
    cwd?: string;
    model?: string;
    [key: string]: unknown;
  };
  /** Parent session ID (for forked sessions) */
  parentId?: string;
  /** Child session IDs */
  children?: string[];
}

export interface SessionCreateOptions {
  /** Session name */
  name?: string;
  /** Session type */
  type?: SessionType;
  /** Parent session ID (for fork) */
  parentId?: string;
  /** Initial messages */
  messages?: SessionMessage[];
  /** Metadata */
  metadata?: Record<string, unknown>;
}

export interface SessionListOptions {
  /** Filter by status */
  status?: SessionStatus;
  /** Filter by type */
  type?: SessionType;
  /** Limit results */
  limit?: number;
  /** Sort order */
  order?: 'asc' | 'desc';
}

export interface SessionStorage {
  /** Save session */
  save(session: Session): Promise<void>;
  /** Load session by ID */
  load(id: string): Promise<Session | null>;
  /** Delete session */
  delete(id: string): Promise<boolean>;
  /** List sessions */
  list(options?: SessionListOptions): Promise<Session[]>;
  /** Search sessions */
  search(query: string): Promise<Session[]>;
}
