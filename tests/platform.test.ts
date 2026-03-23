import { describe, it, expect } from 'vitest';
import { 
  detectPlatform, 
  getPlatformFamily, 
  getPackageManager,
  getArchitecture 
} from '../src/core/platform.js';

describe('Platform Detection', () => {
  it('should detect current platform', () => {
    const platform = detectPlatform();
    expect(['termux', 'arch', 'debian', 'ubuntu', 'fedora', 'gnu-linux']).toContain(platform);
  });

  it('should get platform family', () => {
    const platform = detectPlatform();
    const family = getPlatformFamily(platform);
    expect(family).toBeDefined();
  });

  it('should get package manager', () => {
    const platform = detectPlatform();
    const pkgmgr = getPackageManager(platform);
    expect(['pacman', 'apt', 'dnf', 'yum', 'unknown']).toContain(pkgmgr);
  });

  it('should get architecture', () => {
    const arch = getArchitecture();
    expect(['x86_64', 'aarch64', 'arm']).toContain(arch);
  });
});
