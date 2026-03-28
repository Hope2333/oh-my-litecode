/**
 * Session Summary Hook
 * 
 * Generates summaries of conversation sessions.
 */

export interface SessionMessage {
  role: string;
  content: string;
}

export async function generateSummary(messages: SessionMessage[]): Promise<string> {
  if (messages.length === 0) {
    return 'Empty session';
  }
  
  // Simple summary: first and last message preview
  const firstMsg = messages[0]?.content.slice(0, 50) || '';
  const lastMsg = messages[messages.length - 1]?.content.slice(0, 50) || '';
  
  return `Session (${messages.length} messages): "${firstMsg}..." → "${lastMsg}..."`;
}

export function createSessionSummaryHook() {
  return async (sessionId: string, messages: SessionMessage[]): Promise<string> => {
    return generateSummary(messages);
  };
}
