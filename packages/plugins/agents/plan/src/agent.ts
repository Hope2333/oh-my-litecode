import type { PlanConfig, Plan, PlanStep } from './types.js';

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

export class PlanAgent {
  public readonly name = 'plan';
  public readonly version = '0.2.0';
  
  private config: PlanConfig;
  private hooks: AgentHooks;
  private initialized: boolean;
  private plans: Map<string, Plan>;

  constructor() {
    this.initialized = false;
    this.plans = new Map();
    this.config = { defaultSteps: [], autoExecute: false };
    this.hooks = {};
  }

  async initialize(config: Record<string, unknown>): Promise<void> {
    this.config = { ...this.config, ...config };
    this.initialized = true;
  }

  async shutdown(): Promise<void> {
    this.initialized = false;
    this.plans.clear();
  }

  async process(message: AgentMessage): Promise<AgentResponse> {
    if (!this.initialized) return { success: false, error: 'Not initialized' };

    try {
      if (this.hooks.preProcess) await this.hooks.preProcess(message);

      const content = message.content.toLowerCase();
      let response: AgentResponse;

      if (content.includes('create plan')) {
        const plan = this.createPlan('New Plan');
        response = { success: true, content: `Created plan: ${plan.id}` };
      } else if (content.includes('list plans')) {
        response = { success: true, content: `Plans: ${this.plans.size}` };
      } else {
        response = { success: true, content: 'Plan agent ready. Use "create plan" or "list plans".' };
      }

      if (this.hooks.postProcess) await this.hooks.postProcess(response);
      return response;
    } catch (error) {
      return { success: false, error: error instanceof Error ? error.message : 'Error' };
    }
  }

  private createPlan(name: string): Plan {
    const id = `plan-${Date.now()}`;
    const plan: Plan = { id, name, steps: [], createdAt: new Date() };
    this.plans.set(id, plan);
    return plan;
  }

  getHooks(): AgentHooks { return this.hooks; }
}
