/**
 * Cache Types - OML Modules
 */

export type CacheStrategy = 'lru' | 'lfu' | 'fifo';

export interface CacheConfig {
  maxSize: number;
  ttl?: number; // Time to live in ms
  strategy?: CacheStrategy;
}

export interface CacheEntry<T> {
  value: T;
  timestamp: number;
  hits: number;
}

export interface CacheStats {
  size: number;
  hits: number;
  misses: number;
  evictions: number;
}
