/**
 * Platform Detector - OML Core
 * 
 * Detects the current platform and handles fakehome nesting.
 */

import * as os from 'os';
import * as fs from 'fs';
import * as path from 'path';
import type { PlatformType, ArchType, PlatformInfo, FakeHomeResult } from './types.js';

export class PlatformDetector {
  private platform: PlatformType | null = null;
  private arch: ArchType | null = null;

  /**
   * Detect the current platform type
   */
  detectPlatform(): PlatformType {
    if (this.platform) {
      return this.platform;
    }

    // Termux (Android) - highest priority
    if (fs.existsSync('/data/data/com.termux/files/usr')) {
      this.platform = 'termux';
      return this.platform;
    }

    const platform = os.platform();
    
    if (platform === 'darwin') {
      this.platform = 'macos';
      return this.platform;
    }

    if (platform === 'win32') {
      this.platform = 'windows';
      return this.platform;
    }

    // Linux distro detection
    if (fs.existsSync('/etc/arch-release')) {
      this.platform = 'arch';
    } else if (fs.existsSync('/etc/manjaro-release')) {
      this.platform = 'manjaro';
    } else if (fs.existsSync('/etc/endeavouros-release')) {
      this.platform = 'endeavouros';
    } else if (fs.existsSync('/etc/debian_version')) {
      this.platform = 'debian';
    } else if (fs.existsSync('/etc/ubuntu-release')) {
      this.platform = 'ubuntu';
    } else if (fs.existsSync('/etc/fedora-release')) {
      this.platform = 'fedora';
    } else if (fs.existsSync('/etc/redhat-release')) {
      this.platform = 'rhel';
    } else if (fs.existsSync('/etc/almalinux-release')) {
      this.platform = 'rhel';
    } else if (fs.existsSync('/etc/rocky-release')) {
      this.platform = 'rhel';
    } else if (fs.existsSync('/etc/SuSE-release') || fs.existsSync('/etc/opensuse-release')) {
      this.platform = 'opensuse';
    } else if (fs.existsSync('/etc/alpine-release')) {
      this.platform = 'alpine';
    } else {
      this.platform = 'linux';
    }

    return this.platform;
  }

  /**
   * Detect the current architecture
   */
  detectArch(): ArchType {
    if (this.arch) {
      return this.arch;
    }

    const arch = os.arch();
    
    switch (arch) {
      case 'x64':
        this.arch = 'x64';
        break;
      case 'arm64':
        this.arch = 'arm64';
        break;
      case 'arm':
        this.arch = 'arm';
        break;
      default:
        this.arch = 'x86';
    }

    return this.arch;
  }

  /**
   * Detect fakehome nesting
   */
  detectFakeHomeNesting(): FakeHomeResult {
    const home = process.env.HOME || os.homedir();
    const nestedPaths: string[] = [];
    
    // Check if HOME contains nested .local/home pattern
    const nestedPattern = /\/\.local\/home\/[^/]+\/\.local\/home\//;
    const isNested = nestedPattern.test(home);

    if (isNested) {
      // Extract all nested paths
      const matches = home.matchAll(/(\/\.local\/home\/[^/]+)/g);
      for (const match of matches) {
        nestedPaths.push(match[1]);
      }

      // Extract real home (outermost)
      const realHome = home.replace(/\/\.local\/home\/[^/]+$/, '');

      return {
        isNested: true,
        currentHome: home,
        realHome,
        nestedPaths,
      };
    }

    return {
      isNested: false,
      currentHome: home,
      nestedPaths: [],
    };
  }

  /**
   * Fix fakehome nesting by restoring to real HOME
   */
  async fixFakeHomeNesting(): Promise<{ fixed: boolean; originalHome?: string }> {
    const result = this.detectFakeHomeNesting();
    
    if (!result.isNested || !result.realHome) {
      return { fixed: false };
    }

    // Verify real home is valid
    if (!fs.existsSync(result.realHome)) {
      return { fixed: false };
    }

    const originalHome = process.env.HOME;
    
    // Set HOME to real home
    process.env.HOME = result.realHome;
    
    return {
      fixed: true,
      originalHome,
    };
  }

  /**
   * Get complete platform information
   */
  async getPlatformInfo(): Promise<PlatformInfo> {
    const type = this.detectPlatform();
    const arch = this.detectArch();
    const fakeHomeResult = this.detectFakeHomeNesting();
    
    // Fix nesting if detected
    const fixResult = await this.fixFakeHomeNesting();
    
    const homeDir = process.env.HOME || os.homedir();
    const isFakeHome = homeDir.includes('/.local/home/');

    return {
      type,
      arch,
      homeDir,
      isFakeHome,
      fakeHomeOriginal: fixResult.originalHome,
      isNested: fakeHomeResult.isNested,
    };
  }
}

// Default detector instance
let defaultDetector: PlatformDetector | null = null;

export function getDefaultDetector(): PlatformDetector {
  if (!defaultDetector) {
    defaultDetector = new PlatformDetector();
  }
  return defaultDetector;
}

// Convenience functions
export const detectPlatform = () => getDefaultDetector().detectPlatform();
export const detectArch = () => getDefaultDetector().detectArch();
export const detectFakeHomeNesting = () => getDefaultDetector().detectFakeHomeNesting();
export const fixFakeHomeNesting = () => getDefaultDetector().fixFakeHomeNesting();
export const getPlatformInfo = () => getDefaultDetector().getPlatformInfo();
