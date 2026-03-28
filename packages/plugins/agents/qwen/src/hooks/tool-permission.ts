/**
 * Tool Permission Hook
 * 
 * Checks tool permissions before execution.
 */

export interface ToolPermissionConfig {
  allowedTools?: string[];
  blockedTools?: string[];
}

export async function checkToolPermission(
  toolName: string,
  args: Record<string, unknown>,
  config?: ToolPermissionConfig
): Promise<boolean> {
  // Default: allow all tools
  if (!config) return true;
  
  // Check blocked tools first
  if (config.blockedTools?.includes(toolName)) {
    return false;
  }
  
  // Check allowed tools if specified
  if (config.allowedTools && !config.allowedTools.includes(toolName)) {
    return false;
  }
  
  return true;
}

export function createToolPermissionHook(config?: ToolPermissionConfig) {
  return async (toolName: string, args: Record<string, unknown>): Promise<boolean> => {
    return checkToolPermission(toolName, args, config);
  };
}
