import { describe, it, expect } from 'vitest';
import { createPromptScanHook } from '../src/hooks/prompt-scan.js';
import { createResultCacheHook, getCache, setCache } from '../src/hooks/result-cache.js';
import { createToolPermissionHook } from '../src/hooks/tool-permission.js';
import { createSessionSummaryHook } from '../src/hooks/session-summary.js';

describe('Qwen Hooks', () => {
  describe('promptScan', () => {
    it('should extract keywords', async () => {
      const hook = createPromptScanHook();
      const result = await hook('Hello world, this is a test prompt');
      expect(result).toContain('hello');
      expect(result).toContain('world');
    });
  });

  describe('resultCache', () => {
    it('should cache and retrieve values', async () => {
      await setCache('test-key', 'test-value');
      const value = await getCache('test-key');
      expect(value).toBe('test-value');
    });
  });

  describe('toolPermission', () => {
    it('should allow tools by default', async () => {
      const hook = createToolPermissionHook();
      const result = await hook('test-tool', {});
      expect(result).toBe(true);
    });

    it('should block blocked tools', async () => {
      const hook = createToolPermissionHook({ blockedTools: ['dangerous'] });
      const result = await hook('dangerous', {});
      expect(result).toBe(false);
    });
  });

  describe('sessionSummary', () => {
    it('should generate summary', async () => {
      const hook = createSessionSummaryHook();
      const messages = [
        { role: 'user', content: 'Hello' },
        { role: 'assistant', content: 'Hi there' },
      ];
      const summary = await hook('session-1', messages);
      expect(summary).toContain('2 messages');
    });
  });
});
