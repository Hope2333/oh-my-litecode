export interface PlanConfig {
  defaultSteps: string[];
  autoExecute: boolean;
}

export interface PlanStep {
  id: string;
  description: string;
  status: 'pending' | 'in-progress' | 'completed' | 'failed';
}

export interface Plan {
  id: string;
  name: string;
  steps: PlanStep[];
  createdAt: Date;
}
