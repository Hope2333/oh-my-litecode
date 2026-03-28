export async function notifyPlanUpdate(planId: string, message: string): Promise<void> {
  console.log(`[Plan ${planId}] ${message}`);
}
