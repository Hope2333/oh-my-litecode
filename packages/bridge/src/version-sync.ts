/**
 * Version Sync - AI-LTC Bridge version compatibility checking.
 *
 * Detects version drift between installed AI-LTC framework version
 * and the version declared in OML config.
 */

import { readFile } from 'node:fs/promises';
import { VersionInfo } from './types.js';

export interface VersionSyncOptions {
  aiLtcRoot: string;
  configPath: string;
}

export type DriftLevel = 'none' | 'patch' | 'minor' | 'major';

export interface DriftInfo {
  installed: string;
  available: string;
  drift: DriftLevel;
}

interface ParsedVersion {
  major: number;
  minor: number;
  patch: number;
  raw: string;
}

/**
 * Parse a version string like "v1.5.10" or "v1.5.10-sqwen36pre".
 * Strips suffix after the first non-digit in the patch segment.
 */
export function parseVersion(raw: string): ParsedVersion {
  const cleaned = raw.replace(/^v/, '');
  const match = cleaned.match(/^(\d+)\.(\d+)\.(\d+)/);
  if (!match) {
    throw new Error(`Invalid version format: "${raw}". Expected "vMAJOR.MINOR.PATCH" optionally with a suffix.`);
  }
  return {
    major: Number.parseInt(match[1], 10),
    minor: Number.parseInt(match[2], 10),
    patch: Number.parseInt(match[3], 10),
    raw,
  };
}

export class VersionSync {
  private readonly aiLtcRoot: string;
  private readonly configPath: string;
  private _lastCheck: string | null = null;
  private _lastInfo: VersionInfo | null = null;

  constructor(options: VersionSyncOptions) {
    this.aiLtcRoot = options.aiLtcRoot;
    this.configPath = options.configPath;
  }

  private async readFrameworkVersion(): Promise<string> {
    const versionPath = `${this.aiLtcRoot}/VERSION`;
    const content = await readFile(versionPath, 'utf-8');
    return content.trim();
  }

  private async readConfigVersion(): Promise<string> {
    const content = await readFile(this.configPath, 'utf-8');
    const config = JSON.parse(content) as Record<string, unknown>;
    const system = config.system as Record<string, unknown> | undefined;
    const frameworkVersion = system?.framework_version as string | undefined;
    if (!frameworkVersion) {
      throw new Error(
        `framework_version not found in ${this.configPath}. Expected config.system.framework_version.`,
      );
    }
    return frameworkVersion;
  }

  async check(): Promise<VersionInfo> {
    const [installedRaw, availableRaw] = await Promise.all([
      this.readFrameworkVersion(),
      this.readConfigVersion(),
    ]);

    const compatible = await this.isCompatible();

    const info: VersionInfo = {
      framework: installedRaw,
      bridge: availableRaw,
      compatible,
      lastCheck: new Date().toISOString(),
    };

    this._lastCheck = info.lastCheck;
    this._lastInfo = info;

    return info;
  }

  async isCompatible(): Promise<boolean> {
    const [installedRaw, availableRaw] = await Promise.all([
      this.readFrameworkVersion(),
      this.readConfigVersion(),
    ]);

    const installed = parseVersion(installedRaw);
    const available = parseVersion(availableRaw);

    return installed.major === available.major && installed.minor === available.minor;
  }

  async getDrift(): Promise<DriftInfo> {
    const [installedRaw, availableRaw] = await Promise.all([
      this.readFrameworkVersion(),
      this.readConfigVersion(),
    ]);

    const installed = parseVersion(installedRaw);
    const available = parseVersion(availableRaw);

    let drift: DriftLevel;

    if (
      installed.major === available.major &&
      installed.minor === available.minor &&
      installed.patch === available.patch
    ) {
      drift = 'none';
    } else if (installed.major === available.major && installed.minor === available.minor) {
      drift = 'patch';
    } else if (installed.major === available.major) {
      drift = 'minor';
    } else {
      drift = 'major';
    }

    return {
      installed: installedRaw,
      available: availableRaw,
      drift,
    };
  }

  getLastCheck(): string | null {
    return this._lastCheck;
  }
}

export async function checkVersionCompatibility(
  aiLtcRoot: string,
  configPath: string,
): Promise<VersionInfo> {
  const sync = new VersionSync({ aiLtcRoot, configPath });
  return sync.check();
}
