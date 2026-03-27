/**
 * OAuth Switcher - OML Modules
 * 
 * OAuth token switching management.
 */

import * as fs from 'fs';
import * as path from 'path';

export interface OAuthToken {
  alias: string;
  accessToken: string;
  refreshToken: string;
  expiryDate: number;
  createdAt: Date;
}

export interface OAuthSwitcherConfig {
  tokensFile: string;
}

export class OAuthSwitcher {
  private tokens: Map<string, OAuthToken>;
  private currentAlias: string | null = null;
  private config: OAuthSwitcherConfig;

  constructor(config?: Partial<OAuthSwitcherConfig>) {
    this.config = {
      tokensFile: path.join(process.env.HOME || '', '.qwenx', 'secrets', 'oauth-tokens.json'),
      ...config,
    };
    this.tokens = new Map();
    this.load();
  }

  private load(): void {
    try {
      if (fs.existsSync(this.config.tokensFile)) {
        const data = fs.readFileSync(this.config.tokensFile, 'utf-8');
        const tokens = JSON.parse(data);
        tokens.forEach((t: OAuthToken) => {
          this.tokens.set(t.alias, {
            ...t,
            createdAt: new Date(t.createdAt),
          });
        });
      }
    } catch (error) {
      console.error('Failed to load tokens:', error);
    }
  }

  private save(): void {
    try {
      const dir = path.dirname(this.config.tokensFile);
      if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
      }

      const data = JSON.stringify(Array.from(this.tokens.values()), null, 2);
      fs.writeFileSync(this.config.tokensFile, data, 'utf-8');
      fs.chmodSync(this.config.tokensFile, 0o600);
    } catch (error) {
      console.error('Failed to save tokens:', error);
    }
  }

  add(alias: string, token: OAuthToken): void {
    this.tokens.set(alias, token);
    this.save();
  }

  remove(alias: string): boolean {
    const deleted = this.tokens.delete(alias);
    if (deleted) {
      if (this.currentAlias === alias) {
        this.currentAlias = null;
      }
      this.save();
    }
    return deleted;
  }

  switch(alias: string): boolean {
    if (!this.tokens.has(alias)) {
      return false;
    }
    this.currentAlias = alias;
    return true;
  }

  getCurrent(): OAuthToken | null {
    if (!this.currentAlias) return null;
    return this.tokens.get(this.currentAlias) || null;
  }

  isTokenExpired(token: OAuthToken): boolean {
    const now = Date.now();
    // Add 5 minute buffer
    return token.expiryDate < now + 300000;
  }

  isCurrentTokenExpired(): boolean {
    const token = this.getCurrent();
    if (!token) return true;
    return this.isTokenExpired(token);
  }

  list(): OAuthToken[] {
    return Array.from(this.tokens.values());
  }
}
