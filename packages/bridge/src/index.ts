// Bridge barrel exports
export * from './types.js';
export { BridgeConfig, loadBridgeConfig } from './config.js';
export { EventMapper, getEventMap, mapTransitionToHook, mapHookToTransition } from './events.js';
export { OmlBridge } from './bridge.js';
export { VersionSync, checkVersionCompatibility } from './version-sync.js';
export { MemorySync } from './memory.js';
export type { MemoryEntry } from './memory.js';
export { ContextManager } from './context-manager.js';
export type { ContextSummary } from './context-manager.js';
export { ErrorTracker } from './error-tracker.js';
export type { ErrorPattern } from './error-tracker.js';

// Platform adapters
export {
  PlatformAdapter,
  AdapterRegistry,
  registry,
} from './adapters/index.js';
export { OpenCodeAdapter } from './adapters/opencode-adapter.js';
export { ClaudeCodeAdapter } from './adapters/claude-adapter.js';
