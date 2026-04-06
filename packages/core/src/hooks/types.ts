/**
 * Hooks Types - OML Core
 * 
 * Type definitions for hooks system.
 */

export type HookEvent = 
  // Session lifecycle
  | 'session:create'
  | 'session:delete'
  | 'session:stop'
  // AI interaction
  | 'prompt:submit'
  | 'tool:pre-use'
  | 'tool:post-use'
  | 'response:receive'
  // AI-LTC Bridge events
  | 'bridge:execution:start'
  | 'bridge:review:start'
  | 'bridge:optimize:start'
  | 'bridge:checkpoint:create'
  | 'bridge:blocked:notify'
  | 'bridge:blocked:resolve'
  | 'bridge:done:notify';

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
