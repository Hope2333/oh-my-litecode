/**
 * OML Platform Types
 * 
 * Type definitions for platform detection and adaptation
 */

export type PlatformName = 
  | 'termux'
  | 'arch'
  | 'manjaro'
  | 'endeavouros'
  | 'debian'
  | 'ubuntu'
  | 'linuxmint'
  | 'fedora'
  | 'rhel'
  | 'centos'
  | 'opensuse'
  | 'alpine'
  | 'gnu-linux';

export type PlatformFamily = 
  | 'termux'
  | 'arch'
  | 'debian'
  | 'rhel'
  | 'opensuse'
  | 'alpine'
  | 'gnu-linux';

export type PackageManager = 
  | 'pacman'
  | 'apt'
  | 'dnf'
  | 'yum'
  | 'zypper'
  | 'apk'
  | 'pkg'
  | 'unknown';

export interface PlatformInfo {
  /** Detected platform name */
  name: PlatformName;
  /** Platform family for config selection */
  family: PlatformFamily;
  /** Package manager for this platform */
  pkgmgr: PackageManager;
  /** System architecture */
  arch: string;
  /** Prefix path (e.g., /usr or /data/data/com.termux/files/usr) */
  prefix: string;
  /** Whether running in fake HOME isolation */
  isFakeHome: boolean;
}

export interface PlatformDetectionResult {
  success: boolean;
  platform?: PlatformName;
  error?: string;
}
