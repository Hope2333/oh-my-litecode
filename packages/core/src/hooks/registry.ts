/**
 * Hooks Registry - OML Core
 * 
 * Registry for hook handlers.
 */

import type { HookEvent, HookHandler, HookRegistry as HookRegistryInterface } from './types.js';

export class HooksRegistry implements HookRegistryInterface {
  private handlers: Map<HookEvent, Map<string, HookHandler>>;

  constructor() {
    this.handlers = new Map();
  }

  get(event: HookEvent): HookHandler[] {
    const eventHandlers = this.handlers.get(event);
    if (!eventHandlers) {
      return [];
    }

    // Return enabled handlers sorted by priority (lower = higher priority)
    return Array.from(eventHandlers.values())
      .filter(h => h.enabled)
      .sort((a, b) => a.priority - b.priority);
  }

  add(handler: HookHandler): void {
    const { event } = handler as HookHandler & { event: HookEvent };
    
    // Need to get event from context - fix this
    // For now, we'll add a method to register with event
  }

  register(event: HookEvent, handler: HookHandler): void {
    if (!this.handlers.has(event)) {
      this.handlers.set(event, new Map());
    }
    this.handlers.get(event)!.set(handler.name, handler);
  }

  remove(name: string): void {
    for (const [, handlers] of this.handlers) {
      handlers.delete(name);
    }
  }

  enable(name: string): void {
    for (const [, handlers] of this.handlers) {
      const handler = handlers.get(name);
      if (handler) {
        handler.enabled = true;
      }
    }
  }

  disable(name: string): void {
    for (const [, handlers] of this.handlers) {
      const handler = handlers.get(name);
      if (handler) {
        handler.enabled = false;
      }
    }
  }

  isEnabled(name: string): boolean {
    for (const [, handlers] of this.handlers) {
      const handler = handlers.get(name);
      if (handler) {
        return handler.enabled;
      }
    }
    return false;
  }

  list(): string[] {
    const names = new Set<string>();
    for (const [, handlers] of this.handlers) {
      for (const name of handlers.keys()) {
        names.add(name);
      }
    }
    return Array.from(names);
  }
}
