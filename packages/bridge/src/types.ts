export type AiLtcPhase = 'INIT' | 'HANDOFF_READY' | 'EXECUTION' | 'REVIEW' | 'OPTIMIZER' | 'CHECKPOINT' | 'BLOCKED';

export type BridgeStatus = 'idle' | 'running' | 'blocked' | 'reviewing' | 'optimizing' | 'done';

export type BridgeErrorCode = 'OML_UNAVAILABLE' | 'CAPABILITY_NOT_FOUND' | 'TASK_TIMEOUT' | 'PROTOCOL_ERROR' | 'VERSION_INCOMPATIBLE';

export interface BridgeErrorInfo {
  type: string;
  message: string;
  recoveryAction: string;
  recoveryAttempted: number;
}

export interface BridgeState {
  phase: AiLtcPhase;
  status: BridgeStatus;
  errorState?: BridgeErrorInfo;
  contextSummary: string;
  lastUpdate: string;
  lastUpdatedBy: string;
}

export class BridgeError extends Error {
  code: BridgeErrorCode;
  details: string;
  recoverable: boolean;

  constructor(code: BridgeErrorCode, message: string, details: string, recoverable: boolean) {
    super(message);
    this.name = 'BridgeError';
    this.code = code;
    this.details = details;
    this.recoverable = recoverable;
  }
}

export interface BridgeEvent {
  type: string;
  phase: AiLtcPhase;
  payload: Record<string, unknown>;
  timestamp: Date;
  sessionId?: string;
}

export interface TaskPayload {
  taskId: string;
  type: 'subagent' | 'skill' | 'mcp';
  capability: string;
  payload: {
    description: string;
    scope?: string;
    timeout?: number;
  };
  metadata: {
    sessionId: string;
    phase: string;
    priority: number;
  };
}

export interface TaskResult {
  taskId: string;
  status: 'success' | 'error' | 'timeout';
  result?: {
    findings?: string[];
    context?: string;
  };
  error?: string;
  duration: number;
  workerId?: string;
}

export type BridgeHookEvent =
  | 'bridge:execution:start'
  | 'bridge:review:start'
  | 'bridge:optimize:start'
  | 'bridge:checkpoint:create'
  | 'bridge:blocked:notify'
  | 'bridge:blocked:resolve'
  | 'bridge:done:notify';

export interface EventMapping {
  transition: string;
  hook: BridgeHookEvent;
  payloadSchema: Record<string, string>;
}

export interface BridgeConfig {
  enabled: boolean;
  aiLtcRoot: string;
  configFile: string;
  autoStart: boolean;
  logLevel: 'debug' | 'info' | 'warn' | 'error';
}

export interface VersionInfo {
  framework: string;
  bridge: string;
  compatible: boolean;
  lastCheck: string;
}
