/**
 * Qwen Agent - Main Agent Class
 */

import type { QwenConfig, QwenMessage, QwenResponse, QwenHooks } from './types.js';

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

export interface AgentHooks {
  preProcess?: (message: AgentMessage) => Promise<void>;
  postProcess?: (response: AgentResponse) => Promise<void>;
}

export class QwenAgent {
  public readonly name = 'qwen';
  public readonly version = '0.2.0';
  
  private config: QwenConfig;
  private hooks: AgentHooks;
  private initialized: boolean;

  constructor() {
    this.initialized = false;
    this.config = {
      apiKey: '',
      baseUrl: '',
      model: 'qwen-plus',
      sessionEnabled: true,
      hooksEnabled: true,
      promptScanEnabled: true,
      toolPermissionEnabled: true,
      resultCacheEnabled: true,
      sessionSummaryEnabled: true,
    };
    this.hooks = {};
  }

  async initialize(config: Record<string, unknown>): Promise<void> {
    this.config = {
      ...this.config,
      apiKey: (config.apiKey as string) || process.env.QWEN_API_KEY || '',
      baseUrl: (config.baseUrl as string) || process.env.QWEN_BASE_URL || '',
      model: (config.model as string) || 'qwen-plus',
    };
    this.initialized = true;
    console.log(`[QwenAgent] Initialized with model: ${this.config.model}`);
  }

  async shutdown(): Promise<void> {
    this.initialized = false;
    console.log('[QwenAgent] Shutdown complete');
  }

  async process(message: AgentMessage): Promise<AgentResponse> {
    if (!this.initialized) {
      return { success: false, error: 'Agent not initialized' };
    }

    try {
      if (this.hooks.preProcess) await this.hooks.preProcess(message);

      const response: AgentResponse = {
        success: true,
        content: `[QwenAgent] Received: ${message.content}`,
      };

      if (this.hooks.postProcess) await this.hooks.postProcess(response);
      return response;
    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Unknown error',
      };
    }
  }

  getHooks(): AgentHooks { return this.hooks; }
  getConfig(): QwenConfig { return { ...this.config }; }
}
