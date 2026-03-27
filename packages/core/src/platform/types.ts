/**
 * Platform Types - OML Core
 * 
 * Type definitions for platform detection.
 */

export type PlatformType = 
  | 'termux' 
  | 'arch' 
  | 'manjaro' 
  | 'endeavouros'
  | 'debian'
  | 'ubuntu'
  | 'fedora'
  | 'rhel'
  | 'opensuse'
  | 'alpine'
  | 'macos'
  | 'windows'
  | 'linux';

export type ArchType = 'x64' | 'arm64' | 'arm' | 'x86';

export interface PlatformInfo {
  type: PlatformType;
  arch: ArchType;
  homeDir: string;
  isFakeHome: boolean;
  fakeHomeOriginal?: string;
  isNested: boolean;
}

export interface FakeHomeResult {
  isNested: boolean;
  currentHome: string;
  realHome?: string;
  nestedPaths: string[];
}
