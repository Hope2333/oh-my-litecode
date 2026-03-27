/**
 * OML Core
 * 
 * Core functionality for Oh-My-Litecode.
 */

// Utils
export * from './utils/index.js';

// Platform (only types and detector that don't conflict)
export type { PlatformType, ArchType, PlatformInfo } from './platform/types.js';
export { PlatformDetector } from './platform/detector.js';

// Session
export * from './session/index.js';

// Plugin
export * from './plugin/index.js';

// Hooks
export * from './hooks/index.js';

// Fakehome
export * from './fakehome/index.js';

// Pool
export * from './pool/index.js';
