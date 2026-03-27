/**
 * Cache Manager - OML Modules
 * 
 * LRU Cache implementation with TTL support.
 */

import type { CacheConfig, CacheEntry, CacheStats, CacheStrategy } from './types.js';

export class CacheManager<T = unknown> {
  private cache: Map<string, CacheEntry<T>>;
  private config: CacheConfig;
  private stats: CacheStats;

  constructor(config?: Partial<CacheConfig>) {
    this.config = {
      maxSize: 100,
      ttl: 60000, // 1 minute default
      strategy: 'lru',
      ...config,
    };
    this.cache = new Map();
    this.stats = { size: 0, hits: 0, misses: 0, evictions: 0 };
  }

  get(key: string): T | null {
    const entry = this.cache.get(key);
    
    if (!entry) {
      this.stats.misses++;
      return null;
    }

    // Check TTL
    if (this.config.ttl && Date.now() - entry.timestamp > this.config.ttl) {
      this.cache.delete(key);
      this.stats.evictions++;
      this.stats.misses++;
      return null;
    }

    entry.hits++;
    this.stats.hits++;
    
    // Move to end for LRU
    if (this.config.strategy === 'lru') {
      this.cache.delete(key);
      this.cache.set(key, entry);
    }

    return entry.value;
  }

  set(key: string, value: T): void {
    // Evict if at capacity
    if (this.cache.size >= this.config.maxSize) {
      this.evict();
    }

    const entry: CacheEntry<T> = {
      value,
      timestamp: Date.now(),
      hits: 0,
    };

    this.cache.set(key, entry);
    this.stats.size = this.cache.size;
  }

  delete(key: string): boolean {
    const deleted = this.cache.delete(key);
    if (deleted) {
      this.stats.size = this.cache.size;
    }
    return deleted;
  }

  clear(): void {
    this.cache.clear();
    this.stats.size = 0;
  }

  has(key: string): boolean {
    const entry = this.cache.get(key);
    if (!entry) return false;
    
    if (this.config.ttl && Date.now() - entry.timestamp > this.config.ttl) {
      this.cache.delete(key);
      return false;
    }
    return true;
  }

  private evict(): void {
    if (this.cache.size === 0) return;

    let keyToDelete: string | undefined = undefined;

    switch (this.config.strategy) {
      case 'fifo':
        // First entry
        keyToDelete = this.cache.keys().next().value;
        break;
      case 'lfu':
        // Least frequently used
        let minHits = Infinity;
        for (const [key, entry] of this.cache) {
          if (entry.hits < minHits) {
            minHits = entry.hits;
            keyToDelete = key;
          }
        }
        break;
      case 'lru':
      default:
        // First entry (oldest)
        keyToDelete = this.cache.keys().next().value;
        break;
    }

    if (keyToDelete) {
      this.cache.delete(keyToDelete);
      this.stats.evictions++;
    }
  }

  getStats(): CacheStats {
    return { ...this.stats };
  }

  getSize(): number {
    return this.cache.size;
  }
}
