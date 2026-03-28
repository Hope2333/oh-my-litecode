/**
 * Plugin Types - Shared across all plugins
 */

export interface Agent {
  name: string;
  version: string;
  initialize(config: Record<string, unknown>): Promise<void>;
  shutdown(): Promise<void>;
  process(message: AgentMessage): Promise<AgentResponse>;
  getHooks(): AgentHooks;
}

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
