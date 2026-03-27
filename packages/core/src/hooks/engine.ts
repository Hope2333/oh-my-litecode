/**
 * Hooks Engine - OML Core
 * 
 * Main hooks engine for executing hooks.
 */

import type { HookEvent, HookContext, HookHandler } from './types.js';
import { HooksRegistry } from './registry.js';
import { EventBus } from './event-bus.js';

export interface HooksEngineOptions {
  enabled?: boolean;
}

export class HooksEngine {
  private registry: HooksRegistry;
  private eventBus: EventBus;
  private enabled: boolean;

  constructor(options?: HooksEngineOptions) {
    this.registry = new HooksRegistry();
    this.eventBus = new EventBus();
    this.enabled = options?.enabled ?? true;
  }

  /**
   * Register a hook handler
   */
  register(event: HookEvent, handler: HookHandler): void {
    this.registry.register(event, handler);
  }

  /**
   * Unregister a hook handler
   */
  unregister(name: string): void {
    this.registry.remove(name);
  }

  /**
   * Trigger hooks for an event
   */
  async trigger(event: HookEvent, data: Record<string, unknown> = {}): Promise<void> {
    if (!this.enabled) {
      return;
    }

    const context: HookContext = {
      event,
      data,
      timestamp: new Date(),
    };

    const handlers = this.registry.get(event);
    
    for (const handler of handlers) {
      try {
        await handler.execute(context);
      } catch (error) {
        console.error(`Hook "${handler.name}" failed:`, error);
      }
    }

    // Also emit via event bus
    await this.eventBus.emit(event, context);
  }

  /**
   * Enable hooks engine
   */
  enable(): void {
    this.enabled = true;
  }

  /**
   * Disable hooks engine
   */
  disable(): void {
    this.enabled = false;
  }

  /**
   * Enable a specific hook
   */
  enableHook(name: string): void {
    this.registry.enable(name);
  }

  /**
   * Disable a specific hook
   */
  disableHook(name: string): void {
    this.registry.disable(name);
  }

  /**
   * List all registered hooks
   */
  listHooks(): string[] {
    return this.registry.list();
  }

  /**
   * Check if a hook is enabled
   */
  isHookEnabled(name: string): boolean {
    return this.registry.isEnabled(name);
  }

  /**
   * Subscribe to events via event bus
   */
  on(event: string, handler: (data: unknown) => void): void {
    this.eventBus.on(event, handler);
  }

  /**
   * Unsubscribe from events
   */
  off(event: string, handler: (data: unknown) => void): void {
    this.eventBus.off(event, handler);
  }
}

// Default hooks engine instance
let defaultEngine: HooksEngine | null = null;

export function getDefaultHooksEngine(): HooksEngine {
  if (!defaultEngine) {
    defaultEngine = new HooksEngine();
  }
  return defaultEngine;
}

// Convenience functions
export const registerHook = (event: HookEvent, handler: HookHandler) => 
  getDefaultHooksEngine().register(event, handler);
export const unregisterHook = (name: string) => 
  getDefaultHooksEngine().unregister(name);
export const triggerHook = (event: HookEvent, data?: Record<string, unknown>) => 
  getDefaultHooksEngine().trigger(event, data);
