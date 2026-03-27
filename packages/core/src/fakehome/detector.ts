/**
 * Fakehome Detector - OML Core
 * 
 * Detects and fixes fakehome nesting.
 */

import * as os from 'os';
import * as fs from 'fs';
import type { FakeHomeResult, FakeHomeFixResult } from './types.js';

export class FakeHomeDetector {
  /**
   * Detect fakehome nesting
   */
  detect(): FakeHomeResult {
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
  async fix(): Promise<FakeHomeFixResult> {
    const result = this.detect();
    
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
      newHome: result.realHome,
    };
  }
}

// Default detector instance
let defaultDetector: FakeHomeDetector | null = null;

export function getDefaultDetector(): FakeHomeDetector {
  if (!defaultDetector) {
    defaultDetector = new FakeHomeDetector();
  }
  return defaultDetector;
}

// Convenience functions
export const detectFakeHome = () => getDefaultDetector().detect();
export const fixFakeHome = () => getDefaultDetector().fix();
