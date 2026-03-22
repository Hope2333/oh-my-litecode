/**
 * OML Platform Detection
 * 
 * TypeScript implementation of platform detection and adaptation
 * Replaces: core/platform.sh
 */

import { execSync } from 'child_process';
import * as fs from 'fs';
import * as path from 'path';
import type { 
  PlatformName, 
  PlatformFamily, 
  PackageManager, 
  PlatformInfo 
} from './platform.types';

/**
 * Detect the current platform
 */
export function detectPlatform(): PlatformName {
  // Termux (Android) - highest priority
  if (fs.existsSync('/data/data/com.termux/files/usr')) {
    return 'termux';
  }

  // Check release files for specific distros
  if (fs.existsSync('/etc/arch-release')) {
    return 'arch';
  }
  if (fs.existsSync('/etc/manjaro-release')) {
    return 'manjaro';
  }
  if (fs.existsSync('/etc/endeavouros-release')) {
    return 'endeavouros';
  }
  if (fs.existsSync('/etc/debian_version')) {
    return 'debian';
  }
  if (fs.existsSync('/etc/ubuntu-release')) {
    return 'ubuntu';
  }
  if (fs.existsSync('/etc/linuxmint-release')) {
    return 'linuxmint';
  }
  if (fs.existsSync('/etc/fedora-release')) {
    return 'fedora';
  }
  if (fs.existsSync('/etc/redhat-release')) {
    return 'rhel';
  }
  if (fs.existsSync('/etc/centos-release')) {
    return 'centos';
  }
  if (fs.existsSync('/etc/SuSE-release') || fs.existsSync('/etc/opensuse-release')) {
    return 'opensuse';
  }

  // Fallback to os-release for modern systems
  if (fs.existsSync('/etc/os-release')) {
    const osRelease = fs.readFileSync('/etc/os-release', 'utf-8');
    const idMatch = osRelease.match(/^ID=(.+)/m);
    if (idMatch) {
      const id = idMatch[1].replace(/['"]/g, '');
      const platformMap: Record<string, PlatformName> = {
        'arch': 'arch',
        'manjaro': 'manjaro',
        'endeavouros': 'endeavouros',
        'debian': 'debian',
        'ubuntu': 'ubuntu',
        'linuxmint': 'linuxmint',
        'mint': 'linuxmint',
        'pop': 'debian',
        'fedora': 'fedora',
        'rhel': 'rhel',
        'centos': 'centos',
        'opensuse-leap': 'opensuse',
        'opensuse-tumbleweed': 'opensuse',
        'opensuse': 'opensuse',
        'alpine': 'alpine',
      };
      return platformMap[id] || 'gnu-linux';
    }
  }

  // Ultimate fallback
  return 'gnu-linux';
}

/**
 * Get platform family for config selection
 */
export function getPlatformFamily(platform: PlatformName): PlatformFamily {
  switch (platform) {
    case 'termux':
      return 'termux';
    case 'debian':
    case 'ubuntu':
    case 'linuxmint':
      return 'debian';
    case 'arch':
    case 'manjaro':
    case 'endeavouros':
      return 'arch';
    case 'fedora':
    case 'rhel':
    case 'centos':
      return 'rhel';
    case 'opensuse':
      return 'opensuse';
    case 'alpine':
      return 'alpine';
    default:
      return 'gnu-linux';
  }
}

/**
 * Get package manager for current platform
 */
export function getPackageManager(platform: PlatformName): PackageManager {
  switch (platform) {
    case 'termux':
      return commandExists('pacman') ? 'pacman' : 'pkg';
    case 'debian':
    case 'ubuntu':
    case 'linuxmint':
      return 'apt';
    case 'arch':
    case 'manjaro':
    case 'endeavouros':
      return 'pacman';
    case 'fedora':
      return 'dnf';
    case 'rhel':
    case 'centos':
      return commandExists('dnf') ? 'dnf' : 'yum';
    case 'opensuse':
      return 'zypper';
    case 'alpine':
      return 'apk';
    default:
      // Try to detect available package manager
      if (commandExists('apt')) return 'apt';
      if (commandExists('dnf')) return 'dnf';
      if (commandExists('yum')) return 'yum';
      if (commandExists('pacman')) return 'pacman';
      if (commandExists('zypper')) return 'zypper';
      if (commandExists('apk')) return 'apk';
      return 'unknown';
  }
}

/**
 * Get prefix path for current platform
 */
export function getPrefixPath(platform: PlatformName): string {
  if (platform === 'termux') {
    return '/data/data/com.termux/files/usr';
  }
  return '/usr/local';
}

/**
 * Get system architecture
 */
export function getArchitecture(): string {
  const arch = process.arch;
  switch (arch) {
    case 'x64':
      return 'x86_64';
    case 'arm64':
      return 'aarch64';
    case 'arm':
      return 'arm';
    default:
      return arch;
  }
}

/**
 * Check if running in fake HOME isolation
 */
export function isFakeHome(): boolean {
  const fakeHome = process.env._FAKEHOME;
  const home = process.env.HOME;
  return !!(fakeHome && home === fakeHome);
}

/**
 * Get complete platform information
 */
export function getPlatformInfo(): PlatformInfo {
  const platform = detectPlatform();
  return {
    name: platform,
    family: getPlatformFamily(platform),
    pkgmgr: getPackageManager(platform),
    arch: getArchitecture(),
    prefix: getPrefixPath(platform),
    isFakeHome: isFakeHome(),
  };
}

/**
 * Check if a command exists
 */
function commandExists(cmd: string): boolean {
  try {
    execSync(`command -v ${cmd}`, { stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
}

/**
 * Install dependencies using platform package manager
 */
export async function installDependencies(
  deps: string[],
  platform?: PlatformName
): Promise<void> {
  const pkgmgr = platform ? getPackageManager(platform) : getPackageManager(detectPlatform());
  
  const commands: Record<PackageManager, string[]> = {
    apt: ['sudo', 'apt', 'install', '-y'],
    pacman: ['sudo', 'pacman', '-S', '--noconfirm'],
    dnf: ['sudo', 'dnf', 'install', '-y'],
    yum: ['sudo', 'yum', 'install', '-y'],
    zypper: ['sudo', 'zypper', 'install', '-y'],
    apk: ['sudo', 'apk', 'add', '--no-cache'],
    pkg: ['pkg', 'install', '-y'],
    unknown: [],
  };

  const cmd = commands[pkgmgr];
  if (cmd.length === 0) {
    throw new Error(`Unsupported package manager: ${pkgmgr}`);
  }

  execSync([...cmd, ...deps].join(' '), { stdio: 'inherit' });
}

// CLI export
if (import.meta.url === `file://${process.argv[1]}`) {
  const info = getPlatformInfo();
  console.log(`Platform: ${info.name}`);
  console.log(`Family: ${info.family}`);
  console.log(`Package Manager: ${info.pkgmgr}`);
  console.log(`Architecture: ${info.arch}`);
  console.log(`Prefix: ${info.prefix}`);
  console.log(`Fake HOME: ${info.isFakeHome}`);
}
