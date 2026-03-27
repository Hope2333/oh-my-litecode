/**
 * Hooks Types - OML Core
 * 
 * Type definitions for hooks system.
 */

export type HookEvent = 
  | 'session:create'
  | 'session:delete'
  | 'prompt:submit'
  | 'tool:pre-use'
  | 'tool:post-use'
  | 'response:receive'
  | 'session:stop';

export interface HookContext {
  event: HookEvent;
  data: Record<string, unknown>;
  timestamp: Date;
}

export interface HookHandler {
  name: string;
  priority: number;
  enabled: boolean;
  execute: (context: HookContext) => Promise<void>;
}

export interface HookRegistry {
  get(event: HookEvent): HookHandler[];
  add(handler: HookHandler): void;
  remove(name: string): void;
  enable(name: string): void;
  disable(name: string): void;
}
