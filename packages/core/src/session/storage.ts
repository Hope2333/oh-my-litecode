/**
 * Session Storage - OML Core
 * 
 * File-based session storage.
 */

import * as fs from 'fs';
import * as path from 'path';
import type { Session } from './types.js';

export interface SessionStorageOptions {
  sessionsDir: string;
}

export class SessionStorage {
  private sessionsDir: string;

  constructor(options: SessionStorageOptions) {
    this.sessionsDir = options.sessionsDir;
    this.ensureDir();
  }

  private ensureDir(): void {
    if (!fs.existsSync(this.sessionsDir)) {
      fs.mkdirSync(this.sessionsDir, { recursive: true });
    }
  }

  private getSessionPath(sessionId: string): string {
    return path.join(this.sessionsDir, `${sessionId}.json`);
  }

  async save(session: Session): Promise<void> {
    const sessionPath = this.getSessionPath(session.id);
    const data = JSON.stringify(session, null, 2);
    await fs.promises.writeFile(sessionPath, data, 'utf-8');
  }

  async load(sessionId: string): Promise<Session | null> {
    const sessionPath = this.getSessionPath(sessionId);
    
    try {
      const data = await fs.promises.readFile(sessionPath, 'utf-8');
      return this.parseSessionData(data);
    } catch (error) {
      return null;
    }
  }

  loadSync(sessionId: string): Session | null {
    const sessionPath = this.getSessionPath(sessionId);
    
    try {
      const data = fs.readFileSync(sessionPath, 'utf-8');
      return this.parseSessionData(data);
    } catch (error) {
      return null;
    }
  }

  private parseSessionData(data: string): Session | null {
    try {
      return JSON.parse(data, (key, value) => {
        if (key === 'createdAt' || key === 'updatedAt' || key === 'timestamp') {
          return new Date(value);
        }
        return value;
      });
    } catch (error) {
      return null;
    }
  }

  async delete(sessionId: string): Promise<boolean> {
    const sessionPath = this.getSessionPath(sessionId);
    
    try {
      await fs.promises.unlink(sessionPath);
      return true;
    } catch (error) {
      return false;
    }
  }

  async list(): Promise<Session[]> {
    this.ensureDir();
    
    const files = await fs.promises.readdir(this.sessionsDir);
    const sessions: Session[] = [];

    for (const file of files) {
      if (file.endsWith('.json')) {
        const session = await this.load(file.replace('.json', ''));
        if (session) {
          sessions.push(session);
        }
      }
    }

    // Sort by updatedAt descending
    sessions.sort((a, b) => b.updatedAt.getTime() - a.updatedAt.getTime());
    
    return sessions;
  }

  async exists(sessionId: string): Promise<boolean> {
    const sessionPath = this.getSessionPath(sessionId);
    
    try {
      await fs.promises.access(sessionPath);
      return true;
    } catch (error) {
      return false;
    }
  }
}
