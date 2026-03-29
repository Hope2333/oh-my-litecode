import type { GitConfig, GitResult } from './types.js';

export interface AgentMessage {
  id: string;
  type: 'user' | 'assistant' | 'system';
  content: string;
  timestamp: Date;
}

export interface AgentResponse {
  success: boolean;
  content?: string;
  error?: string;
}

export class GitAgent {
  public readonly name = 'git';
  public readonly version = '0.2.0';
  private config: GitConfig;
  private initialized: boolean;

  constructor() {
    this.initialized = false;
    this.config = { enabled: true };
  }

  async initialize(config: Record<string, unknown>): Promise<void> {
    this.config = { ...this.config, ...config };
    this.initialized = true;
  }

  async shutdown(): Promise<void> {
    this.initialized = false;
  }

  async process(message: AgentMessage): Promise<AgentResponse> {
    if (!this.initialized) return { success: false, error: 'Not initialized' };
    return { success: true, content: 'git agent ready' };
  }
}
