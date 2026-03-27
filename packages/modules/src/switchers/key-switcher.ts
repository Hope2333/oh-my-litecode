/**
 * Key Switcher - OML Modules
 * 
 * API key switching management.
 */

import * as fs from 'fs';
import * as path from 'path';

export interface ApiKey {
  alias: string;
  key: string;
  createdAt: Date;
  lastUsed?: Date;
}

export interface KeySwitcherConfig {
  keysFile: string;
}

export class KeySwitcher {
  private keys: Map<string, ApiKey>;
  private currentAlias: string | null = null;
  private config: KeySwitcherConfig;

  constructor(config?: Partial<KeySwitcherConfig>) {
    this.config = {
      keysFile: path.join(process.env.HOME || '', '.qwenx', 'secrets', 'api-keys.json'),
      ...config,
    };
    this.keys = new Map();
    this.load();
  }

  private load(): void {
    try {
      if (fs.existsSync(this.config.keysFile)) {
        const data = fs.readFileSync(this.config.keysFile, 'utf-8');
        const keys = JSON.parse(data);
        keys.forEach((k: ApiKey) => {
          this.keys.set(k.alias, {
            ...k,
            createdAt: new Date(k.createdAt),
            lastUsed: k.lastUsed ? new Date(k.lastUsed) : undefined,
          });
        });
      }
    } catch (error) {
      console.error('Failed to load keys:', error);
    }
  }

  private save(): void {
    try {
      const dir = path.dirname(this.config.keysFile);
      if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
      }

      const data = JSON.stringify(Array.from(this.keys.values()), null, 2);
      fs.writeFileSync(this.config.keysFile, data, 'utf-8');
      fs.chmodSync(this.config.keysFile, 0o600);
    } catch (error) {
      console.error('Failed to save keys:', error);
    }
  }

  add(alias: string, key: string): void {
    const apiKey: ApiKey = {
      alias,
      key,
      createdAt: new Date(),
    };
    this.keys.set(alias, apiKey);
    this.save();
  }

  remove(alias: string): boolean {
    const deleted = this.keys.delete(alias);
    if (deleted) {
      if (this.currentAlias === alias) {
        this.currentAlias = null;
      }
      this.save();
    }
    return deleted;
  }

  switch(alias: string): boolean {
    if (!this.keys.has(alias)) {
      return false;
    }
    this.currentAlias = alias;
    const key = this.keys.get(alias);
    if (key) {
      key.lastUsed = new Date();
      this.save();
    }
    return true;
  }

  getCurrent(): ApiKey | null {
    if (!this.currentAlias) return null;
    return this.keys.get(this.currentAlias) || null;
  }

  getCurrentKey(): string | null {
    const key = this.getCurrent();
    return key ? key.key : null;
  }

  list(): ApiKey[] {
    return Array.from(this.keys.values());
  }

  rotate(alias: string, newKey: string): boolean {
    const key = this.keys.get(alias);
    if (!key) return false;
    
    key.key = newKey;
    key.lastUsed = new Date();
    this.save();
    return true;
  }
}
