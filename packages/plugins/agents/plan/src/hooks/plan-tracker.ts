export interface PlanTracker {
  completed: number;
  total: number;
}

export function trackProgress(steps: Array<{ status: string }>): PlanTracker {
  const completed = steps.filter(s => s.status === 'completed').length;
  return { completed, total: steps.length };
}
