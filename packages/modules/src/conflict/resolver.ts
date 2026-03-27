/**
 * Conflict Resolver - OML Modules
 * 
 * Detects and resolves configuration conflicts.
 */

import * as fs from 'fs';
import * as path from 'path';
import * as crypto from 'crypto';
import type { Conflict, ConflictList, ResolveOptions, ResolveStrategy } from './types.js';

export interface ConflictResolverOptions {
  dataDir: string;
}

export class ConflictResolver {
  private conflictsDir: string;
  private conflictLog: string;

  constructor(options: ConflictResolverOptions) {
    this.conflictsDir = path.join(options.dataDir, 'conflicts');
    this.conflictLog = path.join(options.dataDir, 'conflicts.log');
    this.ensureDirs();
  }

  private ensureDirs(): void {
    if (!fs.existsSync(this.conflictsDir)) fs.mkdirSync(this.conflictsDir, { recursive: true });
    const logDir = path.dirname(this.conflictLog);
    if (!fs.existsSync(logDir)) fs.mkdirSync(logDir, { recursive: true });
    if (!fs.existsSync(this.conflictLog)) fs.writeFileSync(this.conflictLog, '# Conflict Log\n');
  }

  /**
   * Detect conflict in file
   */
  detectConflict(file: string, localContent: string, remoteContent: string, baseContent?: string): Conflict | null {
    if (localContent === remoteContent) return null;
    
    const id = `conflict-${crypto.randomBytes(4).toString('hex')}`;
    const conflict: Conflict = {
      id, file, localContent, remoteContent, baseContent,
      status: 'pending', createdAt: new Date(),
    };
    this.saveConflict(conflict);
    return conflict;
  }

  /**
   * Save conflict to file
   */
  private saveConflict(conflict: Conflict): void {
    const conflictFile = path.join(this.conflictsDir, `${conflict.id}.conflict`);
    const content = `# Conflict: ${conflict.id}
# File: ${conflict.file}
# Created: ${conflict.createdAt.toISOString()}
# Status: ${conflict.status}

<<<<<<< LOCAL
${conflict.localContent}
=======
${conflict.remoteContent}
${conflict.baseContent ? `>>>>>>> BASE\n${conflict.baseContent}` : ''}
`;
    fs.writeFileSync(conflictFile, content);
    fs.appendFileSync(this.conflictLog, `[${conflict.createdAt.toISOString()}] New conflict: ${conflict.id} in ${conflict.file}\n`);
  }

  /**
   * List all conflicts
   */
  list(): ConflictList {
    const conflicts: Conflict[] = [];
    if (!fs.existsSync(this.conflictsDir)) return { conflicts, total: 0, pending: 0, resolved: 0 };

    const entries = fs.readdirSync(this.conflictsDir);
    for (const entry of entries) {
      if (!entry.endsWith('.conflict')) continue;
      const conflict = this.loadConflict(entry.replace('.conflict', ''));
      if (conflict) conflicts.push(conflict);
    }
    conflicts.sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime());
    return { conflicts, total: conflicts.length, pending: conflicts.filter(c => c.status === 'pending').length, resolved: conflicts.filter(c => c.status === 'resolved').length };
  }

  /**
   * Load conflict by ID
   */
  private loadConflict(id: string): Conflict | null {
    const conflictFile = path.join(this.conflictsDir, `${id}.conflict`);
    if (!fs.existsSync(conflictFile)) return null;
    try {
      const content = fs.readFileSync(conflictFile, 'utf-8');
      const lines = content.split('\n');
      const conflict: any = { id };
      for (const line of lines) {
        if (line.startsWith('# File:')) conflict.file = line.replace('# File:', '').trim();
        else if (line.startsWith('# Created:')) conflict.createdAt = new Date(line.replace('# Created:', '').trim());
        else if (line.startsWith('# Status:')) conflict.status = line.replace('# Status:', '').trim() as any;
      }
      // Parse content sections
      const localMatch = content.match(/<<<<<<< LOCAL\n([\s\S]*?)\n=======/);
      const remoteMatch = content.match(/=======\n([\s\S]*?)(?:\n>>>>>>>|$)/);
      if (localMatch) conflict.localContent = localMatch[1].trim();
      if (remoteMatch) conflict.remoteContent = remoteMatch[1].trim();
      return conflict as Conflict;
    } catch { return null; }
  }

  /**
   * Get conflict by ID
   */
  get(id: string): Conflict | null { return this.loadConflict(id); }

  /**
   * Resolve conflict
   */
  resolve(id: string, options: ResolveOptions): Conflict | null {
    const conflict = this.get(id);
    if (!conflict) return null;

    let resolvedContent: string;
    switch (options.strategy) {
      case 'local': resolvedContent = conflict.localContent; break;
      case 'remote': resolvedContent = conflict.remoteContent; break;
      case 'merge': resolvedContent = this.mergeContent(conflict.localContent, conflict.remoteContent, conflict.baseContent); break;
      default: return null;
    }

    conflict.status = 'resolved';
    conflict.strategy = options.strategy;
    conflict.resolvedContent = resolvedContent;
    conflict.resolvedAt = new Date();
    this.saveConflict(conflict);
    return conflict;
  }

  /**
   * Merge content (simple merge strategy)
   */
  private mergeContent(local: string, remote: string, base?: string): string {
    // Simple line-by-line merge
    const localLines = local.split('\n');
    const remoteLines = remote.split('\n');
    const baseLines = base ? base.split('\n') : [];
    const result: string[] = [];
    const maxLen = Math.max(localLines.length, remoteLines.length);
    for (let i = 0; i < maxLen; i++) {
      const localLine = localLines[i] || '';
      const remoteLine = remoteLines[i] || '';
      const baseLine = baseLines[i] || '';
      if (localLine === remoteLine) result.push(localLine);
      else if (localLine === baseLine) result.push(remoteLine);
      else if (remoteLine === baseLine) result.push(localLine);
      else result.push(`<<<<<<< CONFLICT\n${localLine}|||${remoteLine}\n>>>>>>>`);
    }
    return result.join('\n');
  }

  /**
   * Resolve all conflicts
   */
  resolveAll(strategy: ResolveStrategy): number {
    const list = this.list();
    let count = 0;
    for (const conflict of list.conflicts) {
      if (conflict.status === 'pending') {
        this.resolve(conflict.id, { strategy });
        count++;
      }
    }
    return count;
  }

  /**
   * Ignore conflict
   */
  ignore(id: string): boolean {
    const conflict = this.get(id);
    if (!conflict) return false;
    conflict.status = 'ignored';
    this.saveConflict(conflict);
    return true;
  }

  /**
   * Delete conflict
   */
  delete(id: string): boolean {
    const conflictFile = path.join(this.conflictsDir, `${id}.conflict`);
    if (!fs.existsSync(conflictFile)) return false;
    fs.unlinkSync(conflictFile);
    return true;
  }

  /**
   * Clear all resolved conflicts
   */
  clearResolved(): number {
    const list = this.list();
    let count = 0;
    for (const conflict of list.conflicts) {
      if (conflict.status === 'resolved' || conflict.status === 'ignored') {
        this.delete(conflict.id);
        count++;
      }
    }
    return count;
  }

  /**
   * Get conflict statistics
   */
  getStats(): { total: number; pending: number; resolved: number; ignored: number } {
    const list = this.list();
    const ignored = list.conflicts.filter(c => c.status === 'ignored').length;
    return { total: list.total, pending: list.pending, resolved: list.resolved, ignored };
  }
}
