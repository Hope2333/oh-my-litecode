import { describe, it, expect } from 'vitest';
import { PlatformDetector } from '../src/platform/detector.js';

describe('PlatformDetector', () => {
  it('should detect platform', () => {
    const detector = new PlatformDetector();
    const platform = detector.detectPlatform();
    
    expect(platform).toBeDefined();
    expect(typeof platform).toBe('string');
  });

  it('should detect architecture', () => {
    const detector = new PlatformDetector();
    const arch = detector.detectArch();
    
    expect(arch).toBeDefined();
    expect(['x64', 'arm64', 'arm', 'x86']).toContain(arch);
  });

  it('should detect fakehome nesting', () => {
    const detector = new PlatformDetector();
    const result = detector.detectFakeHomeNesting();
    
    expect(result).toBeDefined();
    expect(typeof result.isNested).toBe('boolean');
    expect(Array.isArray(result.nestedPaths)).toBe(true);
  });

  it('should get platform info', async () => {
    const detector = new PlatformDetector();
    const info = await detector.getPlatformInfo();
    
    expect(info).toBeDefined();
    expect(info.type).toBeDefined();
    expect(info.arch).toBeDefined();
    expect(info.homeDir).toBeDefined();
  });
});
