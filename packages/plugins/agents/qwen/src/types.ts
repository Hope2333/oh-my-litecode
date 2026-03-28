/**
 * Qwen Agent Types
 */

export interface QwenConfig {
  apiKey: string;
  baseUrl: string;
  model: string;
  sessionEnabled: boolean;
  hooksEnabled: boolean;
  promptScanEnabled: boolean;
  toolPermissionEnabled: boolean;
  resultCacheEnabled: boolean;
  sessionSummaryEnabled: boolean;
}

export interface QwenMessage {
  id: string;
  role: 'user' | 'assistant' | 'system';
  content: string;
  timestamp: Date;
  sessionId?: string;
}

export interface QwenResponse {
  success: boolean;
  content?: string;
  error?: string;
  usage?: {
    promptTokens: number;
    completionTokens: number;
    totalTokens: number;
  };
}

export interface QwenSession {
  id: string;
  name: string;
  messages: QwenMessage[];
  createdAt: Date;
  updatedAt: Date;
}

export interface QwenHookContext {
  sessionId?: string;
  messageId?: string;
  toolName?: string;
  toolArgs?: Record<string, unknown>;
}

export interface QwenHooks {
  preProcess?: (message: QwenMessage) => Promise<void>;
  postProcess?: (response: QwenResponse) => Promise<void>;
  promptScan?: (content: string) => Promise<string>;
  resultCache?: (key: string, result: string) => Promise<void>;
  toolPermission?: (toolName: string, args: Record<string, unknown>) => Promise<boolean>;
  sessionSummary?: (sessionId: string) => Promise<string>;
}
