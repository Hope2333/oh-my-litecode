/**
 * Fakehome Types - OML Core
 * 
 * Type definitions for fakehome management.
 */

export interface FakeHomeResult {
  isNested: boolean;
  currentHome: string;
  realHome?: string;
  nestedPaths: string[];
}

export interface FakeHomeFixResult {
  fixed: boolean;
  originalHome?: string;
  newHome?: string;
}

export interface FakeHomeCleanResult {
  cleaned: number;
  merged: number;
  errors: string[];
}

export interface FakeHomeMergeOptions {
  preserveOriginal?: boolean;
  mergeConfigs?: boolean;
}
