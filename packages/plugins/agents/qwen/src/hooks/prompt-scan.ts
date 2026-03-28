/**
 * Prompt Scan Hook
 * 
 * Scans prompts for context and relevant information.
 */

export interface PromptScanResult {
  context: string[];
  keywords: string[];
  entities: string[];
}

export async function scanPrompt(content: string): Promise<PromptScanResult> {
  // Simple keyword extraction (placeholder for more advanced scanning)
  const keywords = content
    .toLowerCase()
    .match(/\b[a-z]{4,}\b/g) || [];
  
  const uniqueKeywords = [...new Set(keywords)].slice(0, 10);
  
  return {
    context: [],
    keywords: uniqueKeywords,
    entities: [],
  };
}

export function createPromptScanHook() {
  return async (content: string): Promise<string> => {
    const result = await scanPrompt(content);
    return result.keywords.join(', ');
  };
}
