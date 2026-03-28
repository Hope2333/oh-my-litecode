/**
 * Result Cache Hook
 * 
 * Caches results for faster retrieval.
 */

const cache = new Map<string, { value: string; timestamp: number }>();
const DEFAULT_TTL = 300000; // 5 minutes

export interface CacheOptions {
  ttl?: number;
}

export async function getCache(key: string): Promise<string | null> {
  const item = cache.get(key);
  if (!item) return null;
  
  if (Date.now() - item.timestamp > DEFAULT_TTL) {
    cache.delete(key);
    return null;
  }
  
  return item.value;
}

export async function setCache(key: string, value: string, options?: CacheOptions): Promise<void> {
  cache.set(key, {
    value,
    timestamp: Date.now(),
  });
}

export function createResultCacheHook() {
  return async (key: string, result: string): Promise<void> => {
    await setCache(key, result);
  };
}
